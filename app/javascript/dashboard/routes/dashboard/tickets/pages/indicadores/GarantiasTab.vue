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

// Panel de filtros (ajuste visual pedido sobre el mockup v12): una etiqueta
// fija por campo en vez de que el select muestre su nombre solo cuando esta
// vacio. Un solo array en vez de seis bloques <Select> casi identicos en el
// template.
const selectFiltros = computed(() => [
  {
    clave: 'anio',
    label: t('HELIC3_INDICADORES.FILTERS.YEAR'),
    opciones: anioOptions.value,
  },
  {
    clave: 'mes',
    label: t('HELIC3_INDICADORES.FILTERS.MONTH'),
    opciones: mesOptions.value,
  },
  {
    clave: 'cobertura_ciudad_id',
    label: t('HELIC3_INDICADORES.FILTERS.CITY'),
    opciones: ciudadOptions.value,
  },
  {
    clave: 'motivo_garantia_id',
    label: t('HELIC3_INDICADORES.FILTERS.MOTIVE'),
    opciones: motivoOptions.value,
  },
  {
    clave: 'detalle_tipificado_id',
    label: t('HELIC3_INDICADORES.FILTERS.DETAIL'),
    opciones: detalleOptions.value,
  },
  {
    clave: 'proceso_id',
    label: t('HELIC3_INDICADORES.FILTERS.STAGE'),
    opciones: procesoOptions.value,
  },
]);

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

// Ajuste visual (mockup v12): las 4 tarjetas pasan a una sola franja con
// una descripcion corta por metrica, en vez de 4 tarjetas sueltas sin
// contexto de que mide cada numero.
const kpiCards = computed(() => [
  {
    label: t('HELIC3_INDICADORES.GARANTIAS.KPI_TOTAL'),
    valor: datos.value?.kpis.garantias,
    descripcion: t('HELIC3_INDICADORES.GARANTIAS.KPI_TOTAL_DESC'),
    color: 'text-n-slate-12',
  },
  {
    label: t('HELIC3_INDICADORES.GARANTIAS.KPI_SOLVED'),
    valor: datos.value?.kpis.solucionadas,
    descripcion: t('HELIC3_INDICADORES.GARANTIAS.KPI_SOLVED_DESC'),
    color: 'text-n-teal-11',
  },
  {
    label: t('HELIC3_INDICADORES.GARANTIAS.KPI_IN_PROGRESS'),
    valor: datos.value?.kpis.en_proceso,
    descripcion: t('HELIC3_INDICADORES.GARANTIAS.KPI_IN_PROGRESS_DESC'),
    color: 'text-n-amber-11',
  },
  {
    label: t('HELIC3_INDICADORES.GARANTIAS.KPI_PRODUCTS'),
    valor: datos.value?.kpis.productos,
    descripcion: t('HELIC3_INDICADORES.GARANTIAS.KPI_PRODUCTS_DESC'),
    color: 'text-n-slate-12',
  },
]);

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

// Ajuste visual (mockup v12, seccion "Centro de operacion"): por_ciudad suma
// una comparacion visual de barras ademas de la tabla -- sin facturas (eso es
// IND-03), la barra compara CANTIDAD de garantias, no ratio.
const maxPorCiudad = computed(() =>
  Math.max(1, ...(datos.value?.por_ciudad || []).map(fila => fila.cantidad))
);
const anchoBarra = cantidad => (cantidad / maxPorCiudad.value) * 100;

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
    <div class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1">
      <div class="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
        <div
          v-for="filtro in selectFiltros"
          :key="filtro.clave"
          class="min-w-0 space-y-1.5"
        >
          <label class="block text-xs font-medium text-n-slate-11">
            {{ filtro.label }}
          </label>
          <Select
            v-model="filtros[filtro.clave]"
            :options="filtro.opciones"
            :aria-label="filtro.label"
          />
        </div>
      </div>
      <div class="grid gap-3 mt-3 md:grid-cols-[1fr_auto] md:items-end">
        <div class="min-w-0 space-y-1.5">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('HELIC3_INDICADORES.FILTERS.PRODUCT') }}
          </label>
          <Input
            v-model="filtros.producto"
            :placeholder="t('HELIC3_INDICADORES.FILTERS.PRODUCT_PLACEHOLDER')"
          />
        </div>
        <Button
          :label="t('HELIC3_INDICADORES.FILTERS.CLEAR')"
          icon="i-lucide-rotate-ccw"
          variant="outline"
          color="slate"
          size="sm"
          @click="limpiarFiltros"
        />
      </div>
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
        <!-- Tarjetas: una sola franja con descripcion corta por metrica -->
        <div
          class="grid grid-cols-2 divide-x divide-y divide-n-weak rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 md:grid-cols-4 md:divide-y-0 overflow-hidden"
        >
          <div
            v-for="tarjeta in kpiCards"
            :key="tarjeta.label"
            class="p-4 min-w-0"
          >
            <p class="text-sm text-n-slate-11">{{ tarjeta.label }}</p>
            <p
              class="mt-2 text-2xl font-semibold tabular-nums"
              :class="tarjeta.color"
            >
              {{ tarjeta.valor }}
            </p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ tarjeta.descripcion }}
            </p>
          </div>
        </div>

        <!-- Mensual y trimestral -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.GARANTIAS.MONTHLY') }}
            </p>
            <p class="mt-1 mb-2 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.MONTHLY_SUBTITLE') }}
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
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.GARANTIAS.QUARTERLY') }}
            </p>
            <p class="mt-1 mb-2 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.QUARTERLY_SUBTITLE') }}
            </p>
            <BarChart
              v-if="datos.trimestral.length"
              :data="graficaTrimestral"
              :height="ALTURA_GRAFICA"
              :aria-label="t('HELIC3_INDICADORES.GARANTIAS.QUARTERLY')"
            />
          </div>
        </div>

        <!-- Por ciudad: tabla + comparativo de barras (mockup v12, "Centro de operacion") -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-[1.4fr_1fr]">
          <table
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption
              class="p-3 font-semibold text-left caption-top text-n-slate-12"
            >
              {{
                t('HELIC3_INDICADORES.GARANTIAS.BY_CITY')
              }}
            </caption>
            <tbody>
              <tr
                v-for="fila in datos.por_ciudad"
                :key="fila.etiqueta"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 text-n-slate-11">
                  {{ etiquetaDe('BY_CITY', fila.etiqueta) }}
                </td>
                <td
                  class="px-3 py-2 font-medium text-right tabular-nums text-n-slate-12"
                >
                  {{ fila.cantidad }}
                </td>
              </tr>
            </tbody>
          </table>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.GARANTIAS.BY_CITY_CHART') }}
            </p>
            <p class="mt-1 mb-3 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.BY_CITY_CHART_SUBTITLE') }}
            </p>
            <div class="space-y-3">
              <div v-for="fila in datos.por_ciudad" :key="fila.etiqueta">
                <div
                  class="flex items-center justify-between gap-3 text-xs text-n-slate-11"
                >
                  <span class="truncate">
                    {{ etiquetaDe('BY_CITY', fila.etiqueta) }}
                  </span>
                  <span class="tabular-nums shrink-0">{{ fila.cantidad }}</span>
                </div>
                <div class="mt-1.5 h-2 rounded-full bg-n-slate-4">
                  <div
                    class="h-2 rounded-full bg-n-blue-9"
                    :style="{ width: `${anchoBarra(fila.cantidad)}%` }"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Resto de desgloses -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <table
            v-for="seccion in [
              { titulo: 'BY_MOTIVE', filas: datos.por_motivo },
              { titulo: 'BY_DETAIL', filas: datos.por_detalle },
              { titulo: 'BY_STAGE', filas: datos.por_proceso },
              { titulo: 'BY_PRODUCT', filas: datos.por_producto },
            ]"
            :key="seccion.titulo"
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption
              class="p-3 font-semibold text-left caption-top text-n-slate-12"
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
                <td
                  class="px-3 py-2 font-medium text-right tabular-nums text-n-slate-12"
                >
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

<style scoped>
/* Revision de Jhan (PR #123): Select.vue es upstream puro, no se toca (la
   unica excepcion del fork es config/routes.rb). El root de components-next/
   select/Select.vue trae w-fit; en este panel de filtros debe llenar su
   celda de la grilla. Mismo patron ya usado en PqrNuevaPage.vue (#124). */
:deep(.w-fit.relative),
:deep(.w-fit.relative select) {
  width: 100%;
}
</style>
