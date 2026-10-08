<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import { useIndicadoresStore } from 'dashboard/store/helic3/indicadores';

// IND-01: primera pestaña de Indicadores. Garantías que YA están en el CRM,
// con filtros resueltos en el servidor (GET helic3/indicadores/garantias).
// Nº de facturas, ratio y subtotal llegan con IND-03; histórico con IND-04.
const { t, locale } = useI18n();
const store = useStore();
const indicadoresStore = useIndicadoresStore();

// tickets/getCatalogos ya trae coberturas_ciudad/motivos_garantia/detalles_tipificados
// (GAR-05) y procesos_garantia (sumado en este mismo ticket); un solo fetch,
// cacheado por sesión, sin duplicar la llamada que ya hace TicketsPage.
const catalogos = useMapGetter('tickets/getCatalogos');
const datos = computed(() => indicadoresStore.getGarantias);
const cargando = computed(
  () => indicadoresStore.getUIFlags.isFetchingGarantias
);

const ANIO_ACTUAL = new Date().getFullYear();
const ANIOS = Array.from({ length: 5 }, (_, i) => ANIO_ACTUAL - i);
const MESES = Array.from({ length: 12 }, (_, i) => i + 1);
const ALTURA_GRAFICA = 240;
const DEBOUNCE_BUSQUEDA_MS = 300;

const filtros = reactive({
  anio: '',
  mes: '',
  cobertura_ciudad_id: '',
  motivo_garantia_id: '',
  detalle_tipificado_id: '',
  proceso_id: '',
  producto: '',
});

const todos = () => ({ value: '', label: t('HELIC3_INDICADORES.FILTERS.ALL') });
const anioOptions = computed(() => [
  todos(),
  ...ANIOS.map(anio => ({ value: anio, label: String(anio) })),
]);

// N4 (revision de Jhan, PR #113): Karen espera nombres de mes, no 1-12. Mismo
// patron de Intl.DateTimeFormat que HeatmapDateRangeSelector.vue; el dia/anio
// de la fecha de referencia no importa, solo se usa para leer el mes.
const monthFormatter = computed(
  () =>
    new Intl.DateTimeFormat((locale.value || 'es').replace('_', '-'), {
      month: 'long',
    })
);
const nombreDeMes = mes => {
  const nombre = monthFormatter.value.format(new Date(2026, mes - 1, 1));
  return nombre.charAt(0).toUpperCase() + nombre.slice(1);
};
const mesOptions = computed(() => [
  todos(),
  ...MESES.map(mes => ({ value: mes, label: nombreDeMes(mes) })),
]);
const opcionesDe = tipo =>
  computed(() => [
    todos(),
    ...(catalogos.value[tipo] || []).map(fila => ({
      value: fila.id,
      label: fila.nombre,
    })),
  ]);
const ciudadOptions = opcionesDe('coberturas_ciudad');
const motivoOptions = opcionesDe('motivos_garantia');
const detalleOptions = opcionesDe('detalles_tipificados');
const procesoOptions = opcionesDe('procesos_garantia');

const huboError = ref(false);

const cargar = async () => {
  const params = {};
  Object.entries(filtros).forEach(([clave, valor]) => {
    if (valor !== '') params[clave] = valor;
  });
  huboError.value = false;
  try {
    await indicadoresStore.fetchGarantias(params);
  } catch (error) {
    huboError.value = true;
    useAlert(t('HELIC3_INDICADORES.ERROR'));
  }
};

const limpiarFiltros = () => {
  Object.keys(filtros).forEach(clave => {
    filtros[clave] = '';
  });
};

const cargarCatalogos = async () => {
  try {
    await store.dispatch('tickets/getCatalogos');
  } catch (error) {
    // los selectores quedan vacios; cargar() sigue sin depender de esto.
  }
};

onMounted(() => {
  cargarCatalogos();
  cargar();
});

// los selectores aplican de inmediato: los indicadores son pocas filas
// (GROUP BY), no vale la pena filtrar en cliente ni paginar.
watch(
  () => [
    filtros.anio,
    filtros.mes,
    filtros.cobertura_ciudad_id,
    filtros.motivo_garantia_id,
    filtros.detalle_tipificado_id,
    filtros.proceso_id,
  ],
  cargar
);

// producto es texto libre: sin debounce, cada tecla dispararia una consulta y
// una respuesta tardia de un termino viejo podria pisar una mas nueva (mismo
// patron que TicketsPage.vue con su filtro de busqueda).
let debounceBusqueda = null;
watch(
  () => filtros.producto,
  () => {
    clearTimeout(debounceBusqueda);
    debounceBusqueda = setTimeout(cargar, DEBOUNCE_BUSQUEDA_MS);
  }
);

const sinDatos = computed(
  () => !!datos.value && datos.value.kpis.garantias === 0
);

// shared/components/charts/BarChart.vue (@chatwoot/viz): categories + series[].data
// como arreglo de numeros en el mismo orden (patron de superadmin_pages/views/
// dashboard/Index.vue, mas simple que el de ReportContainer, que es para metricas
// con series multiples). Un solo color: estos indicadores solo tienen una serie.
const comoGrafica = filas => ({
  categories: filas.map(fila => fila.etiqueta ?? fila.periodo),
  series: [
    {
      id: 'cantidad',
      label: t('HELIC3_INDICADORES.GARANTIAS.COUNT'),
      color: 'rgb(var(--blue-9))',
      data: filas.map(fila => fila.cantidad),
    },
  ],
});

const graficaMensual = computed(() => comoGrafica(datos.value?.mensual || []));
const graficaTrimestral = computed(() =>
  comoGrafica(datos.value?.trimestral || [])
);

// N3 (revision de Jhan, PR #113): el backend ya no quema "Sin ciudad"/"Sin
// motivo"/etc en español -- devuelve etiqueta: null para que el frontend
// traduzca. por_producto no entra aqui: Jhan solo senalo ciudad/motivo/
// detalle/proceso.
const ETIQUETA_SIN_DATO = {
  BY_CITY: 'NO_CITY',
  BY_MOTIVE: 'NO_MOTIVE',
  BY_DETAIL: 'NO_DETAIL',
  BY_STAGE: 'NO_STAGE',
};
const etiquetaDe = (seccionTitulo, etiqueta) => {
  if (etiqueta !== null && etiqueta !== undefined) return etiqueta;
  const clave = ETIQUETA_SIN_DATO[seccionTitulo];
  return clave ? t(`HELIC3_INDICADORES.GARANTIAS.${clave}`) : etiqueta;
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Filtros -->
    <div
      class="flex flex-wrap items-end gap-3 p-3 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
    >
      <Select
        v-model="filtros.anio"
        :options="anioOptions"
        :aria-label="t('HELIC3_INDICADORES.FILTERS.YEAR')"
      />
      <Select
        v-model="filtros.mes"
        :options="mesOptions"
        :aria-label="t('HELIC3_INDICADORES.FILTERS.MONTH')"
      />
      <Select
        v-model="filtros.cobertura_ciudad_id"
        :options="ciudadOptions"
        :aria-label="t('HELIC3_INDICADORES.FILTERS.CITY')"
      />
      <Select
        v-model="filtros.motivo_garantia_id"
        :options="motivoOptions"
        :aria-label="t('HELIC3_INDICADORES.FILTERS.MOTIVE')"
      />
      <Select
        v-model="filtros.detalle_tipificado_id"
        :options="detalleOptions"
        :aria-label="t('HELIC3_INDICADORES.FILTERS.DETAIL')"
      />
      <Select
        v-model="filtros.proceso_id"
        :options="procesoOptions"
        :aria-label="t('HELIC3_INDICADORES.FILTERS.STAGE')"
      />
      <Input
        v-model="filtros.producto"
        :placeholder="t('HELIC3_INDICADORES.FILTERS.PRODUCT_PLACEHOLDER')"
        class="w-56"
      />
      <Button
        :label="t('HELIC3_INDICADORES.FILTERS.CLEAR')"
        variant="ghost"
        color="slate"
        size="sm"
        @click="limpiarFiltros"
      />
    </div>

    <div v-if="cargando" class="flex justify-center py-12">
      <Spinner :size="32" />
    </div>

    <!-- CA: un fallo del servidor no debe dejar el panel en blanco sin
    explicacion -- queda el aviso (ya avisado tambien por toast) y un boton
    para reintentar sin tener que tocar un filtro. -->
    <div
      v-else-if="huboError"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      <p class="mb-3">{{ t('HELIC3_INDICADORES.ERROR') }}</p>
      <Button
        :label="t('HELIC3_INDICADORES.RETRY')"
        variant="outline"
        color="slate"
        size="sm"
        @click="cargar"
      />
    </div>

    <template v-else-if="datos">
      <p v-if="sinDatos" class="py-12 text-sm text-center text-n-slate-11">
        {{ t('HELIC3_INDICADORES.EMPTY') }}
      </p>

      <template v-else>
        <!-- Tarjetas -->
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="text-sm text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_TOTAL') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ datos.kpis.garantias }}
            </p>
          </div>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="text-sm text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_SOLVED') }}
            </p>
            <p class="text-2xl font-semibold text-n-teal-11">
              {{ datos.kpis.solucionadas }}
            </p>
          </div>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="text-sm text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_IN_PROGRESS') }}
            </p>
            <p class="text-2xl font-semibold text-n-amber-11">
              {{ datos.kpis.en_proceso }}
            </p>
          </div>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="text-sm text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_PRODUCTS') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ datos.kpis.productos }}
            </p>
          </div>
        </div>

        <!-- Mensual y trimestral -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="mb-2 text-sm font-medium text-n-slate-12">
              {{ t('HELIC3_INDICADORES.GARANTIAS.MONTHLY') }}
            </p>
            <BarChart
              v-if="datos.mensual.length"
              :data="graficaMensual"
              :height="ALTURA_GRAFICA"
              :aria-label="t('HELIC3_INDICADORES.GARANTIAS.MONTHLY')"
            />
          </div>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="mb-2 text-sm font-medium text-n-slate-12">
              {{ t('HELIC3_INDICADORES.GARANTIAS.QUARTERLY') }}
            </p>
            <BarChart
              v-if="datos.trimestral.length"
              :data="graficaTrimestral"
              :height="ALTURA_GRAFICA"
              :aria-label="t('HELIC3_INDICADORES.GARANTIAS.QUARTERLY')"
            />
          </div>
        </div>

        <!-- Desgloses -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <table
            v-for="seccion in [
              { titulo: 'BY_CITY', filas: datos.por_ciudad },
              { titulo: 'BY_MOTIVE', filas: datos.por_motivo },
              { titulo: 'BY_DETAIL', filas: datos.por_detalle },
              { titulo: 'BY_STAGE', filas: datos.por_proceso },
              { titulo: 'BY_PRODUCT', filas: datos.por_producto },
            ]"
            :key="seccion.titulo"
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption
              class="p-3 font-medium text-left caption-top text-n-slate-12"
            >
              {{
                t(`HELIC3_INDICADORES.GARANTIAS.${seccion.titulo}`)
              }}
            </caption>
            <tbody>
              <tr
                v-for="fila in seccion.filas"
                :key="fila.etiqueta"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 text-n-slate-11">
                  {{ etiquetaDe(seccion.titulo, fila.etiqueta) }}
                </td>
                <td class="px-3 py-2 font-medium text-right text-n-slate-12">
                  {{ fila.cantidad }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </template>
  </div>
</template>
