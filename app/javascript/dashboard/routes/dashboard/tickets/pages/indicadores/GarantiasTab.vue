<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ComboBarLineChart from 'dashboard/components-next/helic3/ComboBarLineChart.vue';
import { useIndicadoresStore } from 'dashboard/store/helic3/indicadores';
import IndicadoresAPI from 'dashboard/api/helic3/indicadores';
import { downloadBlobResponse } from 'dashboard/helper/helic3/downloadHelper';

// IND-01: primera pestaña de Indicadores. Garantías que YA están en el CRM,
// con filtros resueltos en el servidor (GET helic3/indicadores/garantias).
// Nº de facturas, ratio y subtotal llegan con IND-03; histórico con IND-04.
const { t, locale } = useI18n();
const route = useRoute();
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
// template. Mismo agrupamiento del mockup v12: año/mes/ciudad/motivo/etapa en
// una fila, detalle tipificado junto al producto en la segunda.
const selectFiltrosPrincipales = computed(() => [
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
    label: t('HELIC3_INDICADORES.FILTERS.OPERATION_CENTER'),
    opciones: ciudadOptions.value,
  },
  {
    clave: 'motivo_garantia_id',
    label: t('HELIC3_INDICADORES.FILTERS.MOTIVE'),
    opciones: motivoOptions.value,
  },
  {
    clave: 'proceso_id',
    label: t('HELIC3_INDICADORES.FILTERS.STAGE'),
    opciones: procesoOptions.value,
  },
]);

const detalleFiltro = computed(() => ({
  clave: 'detalle_tipificado_id',
  label: t('HELIC3_INDICADORES.FILTERS.DETAIL'),
  opciones: detalleOptions.value,
}));

const huboError = ref(false);

// mismos filtros para cargar la tabla en pantalla y para descargarla en CSV
// (IND-05): el Excel siempre tiene que coincidir con lo que Karen esta viendo.
const parametrosActuales = () => {
  const params = {};
  Object.entries(filtros).forEach(([clave, valor]) => {
    if (valor !== '') params[clave] = valor;
  });
  return params;
};

const cargar = async () => {
  huboError.value = false;
  try {
    await indicadoresStore.fetchGarantias(parametrosActuales());
  } catch (error) {
    huboError.value = true;
    useAlert(t('HELIC3_INDICADORES.ERROR'));
  }
};

// Detalle de clientes y casos (mockup v12): paginado aparte de los agregados
// de arriba, con los mismos filtros. Un cambio de filtro vuelve a la pagina 1
// (la pagina 7 de un filtro anterior no tiene por que existir en el nuevo).
const casos = computed(() => indicadoresStore.getGarantiasCasos);
const cargandoCasos = computed(
  () => indicadoresStore.getUIFlags.isFetchingGarantiasCasos
);
const casosPagina = ref(1);
const cargarCasos = async () => {
  try {
    await indicadoresStore.fetchGarantiasCasos(
      parametrosActuales(),
      casosPagina.value
    );
  } catch (error) {
    useAlert(t('HELIC3_INDICADORES.ERROR'));
  }
};
const irAPagina = pagina => {
  casosPagina.value = pagina;
  cargarCasos();
};
const cargarTodo = () => {
  cargar();
  casosPagina.value = 1;
  cargarCasos();
};

const descargando = reactive({});
const descargarCsv = async seccion => {
  descargando[seccion] = true;
  try {
    const response = await IndicadoresAPI.garantiasCsv(
      seccion,
      parametrosActuales()
    );
    downloadBlobResponse(response, `indicadores-garantias-${seccion}.csv`);
  } catch (error) {
    useAlert(t('HELIC3_INDICADORES.DOWNLOAD_ERROR'));
  } finally {
    descargando[seccion] = false;
  }
};

// Mismo criterio del mockup (data-action="stats-reset"): un solo click
// vuelve todo a su estado inicial -- filtros y el trimestre desplegado, no
// solo los selectores. El recargo de garantias/casos lo dispara el watch de
// abajo en cuanto cambia algun filtro; si ya estaban todos vacios, no hay
// nada que recargar, pero el trimestre igual se cierra.
// Se despliega al hacer click en un trimestre de "Detalle trimestral" (ver
// seleccionarTrimestre mas abajo); declarado aqui para que limpiarFiltros
// pueda cerrarlo sin dejar un trimestre viejo abierto tras limpiar filtros.
const trimestreSeleccionado = ref(null);

const limpiarFiltros = () => {
  Object.keys(filtros).forEach(clave => {
    filtros[clave] = '';
  });
  trimestreSeleccionado.value = null;
  casosPagina.value = 1;
};

// Ajuste de interactividad (mockup v12): click en un mes de "Detalle mensual"
// o en una tienda de "Centro de operacion" filtra el resto del tablero por
// ese periodo/tienda, igual que data-month/data-center en el mockup.
const seleccionarPeriodo = periodo => {
  const [anio, mes] = periodo.split('-');
  filtros.anio = Number(anio);
  filtros.mes = Number(mes);
};

const seleccionarCiudad = cobertura_ciudad_id => {
  if (!cobertura_ciudad_id) return;
  filtros.cobertura_ciudad_id = cobertura_ciudad_id;
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
  cargarTodo();
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
  cargarTodo
);

// producto es texto libre: sin debounce, cada tecla dispararia una consulta y
// una respuesta tardia de un termino viejo podria pisar una mas nueva (mismo
// patron que TicketsPage.vue con su filtro de busqueda).
let debounceBusqueda = null;
watch(
  () => filtros.producto,
  () => {
    clearTimeout(debounceBusqueda);
    debounceBusqueda = setTimeout(cargarTodo, DEBOUNCE_BUSQUEDA_MS);
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
  {
    label: t('HELIC3_INDICADORES.GARANTIAS.KPI_INVOICES'),
    valor: datos.value?.kpis.facturas,
    descripcion: t('HELIC3_INDICADORES.GARANTIAS.KPI_INVOICES_DESC'),
    color: 'text-n-blue-11',
  },
  {
    label: t('HELIC3_INDICADORES.GARANTIAS.KPI_RATIO'),
    valor: datos.value ? `${datos.value.kpis.ratio}%` : undefined,
    descripcion: t('HELIC3_INDICADORES.GARANTIAS.KPI_RATIO_DESC'),
    color: 'text-n-violet-11',
  },
]);

// "Recuento vs. ratio" (mockup v12): el mockup traza una linea de
// garantias/facturas, pero Facturas todavia no tiene modelo de datos (eso
// es IND-04). Mientras tanto la linea muestra % solucionadas -- un ratio
// real, calculable hoy, no un dato inventado.
const porcentajeSolucionadas = fila =>
  fila.cantidad > 0
    ? Math.round((fila.solucionadas / fila.cantidad) * 1000) / 10
    : 0;

const categoriasMensual = computed(() =>
  (datos.value?.mensual || []).map(fila => fila.periodo)
);
const cantidadMensual = computed(() =>
  (datos.value?.mensual || []).map(fila => fila.cantidad)
);
const porcentajeSolucionadasMensual = computed(() =>
  (datos.value?.mensual || []).map(porcentajeSolucionadas)
);

// Detalle trimestral: click en un trimestre despliega sus meses (mockup v12:
// "al hacer click en la fecha debe dar un diagrama e info sobre esos meses").
// Sin pedir nada al backend: el detalle mensual ya esta completo en memoria,
// solo se filtra por el rango de meses del trimestre elegido.
const seleccionarTrimestre = periodo => {
  trimestreSeleccionado.value =
    trimestreSeleccionado.value === periodo ? null : periodo;
};
const mesesDelTrimestre = periodo => {
  const [anioTexto, trimestreTexto] = periodo.split('-T');
  const trimestre = Number(trimestreTexto);
  const primerMes = (trimestre - 1) * 3 + 1;
  const ultimoMes = trimestre * 3;
  return (datos.value?.mensual || []).filter(fila => {
    const [anioFila, mesFila] = fila.periodo.split('-').map(Number);
    return (
      String(anioFila) === anioTexto &&
      mesFila >= primerMes &&
      mesFila <= ultimoMes
    );
  });
};
const filaTrimestreSeleccionada = computed(() =>
  (datos.value?.trimestral || []).find(
    fila => fila.periodo === trimestreSeleccionado.value
  )
);
const mesesTrimestreSeleccionado = computed(() =>
  trimestreSeleccionado.value
    ? mesesDelTrimestre(trimestreSeleccionado.value)
    : []
);
const categoriasTrimestre = computed(() =>
  mesesTrimestreSeleccionado.value.map(fila => fila.periodo)
);
const cantidadTrimestre = computed(() =>
  mesesTrimestreSeleccionado.value.map(fila => fila.cantidad)
);
const porcentajeSolucionadasTrimestre = computed(() =>
  mesesTrimestreSeleccionado.value.map(porcentajeSolucionadas)
);

// Ajuste visual (mockup v12, seccion "Centro de operacion"): por_ciudad suma
// una comparacion visual de barras ademas de la tabla. IND-03: ya hay
// facturas, asi que la barra compara RATIO (garantias/facturas), igual que
// "Ratio por tienda" del Dash CX -- antes comparaba CANTIDAD porque no
// existia el dato.
const maxRatioPorCiudad = computed(() =>
  Math.max(1, ...(datos.value?.por_ciudad || []).map(fila => fila.ratio))
);
const anchoBarra = ratio => (ratio / maxRatioPorCiudad.value) * 100;

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

// "Detalle de clientes y casos" (mockup v12, data-stats-record/data-month):
// el semaforo ya viene calculado del backend (PLZ-01); aqui solo se traduce
// a color + texto, igual que el resto de etiquetas de esta pantalla.
const COLOR_VENCIMIENTO = {
  rojo: 'text-n-ruby-11',
  amarillo: 'text-n-amber-11',
  verde: 'text-n-slate-11',
  solucionada: 'text-n-teal-11',
};
const colorVencimiento = estado =>
  COLOR_VENCIMIENTO[estado] || 'text-n-slate-11';
const textoVencimiento = fila => {
  if (fila.vencimiento.estado === 'solucionada') {
    return t('HELIC3_INDICADORES.GARANTIAS.CASES.DUE_DONE');
  }
  const dias = fila.vencimiento.saldo_dias_habiles;
  return dias < 0
    ? t('HELIC3_INDICADORES.GARANTIAS.CASES.DUE_OVERDUE', {
        dias: Math.abs(dias),
      })
    : t('HELIC3_INDICADORES.GARANTIAS.CASES.DUE_REMAINING', { dias });
};

// Mismo patron de PqrDetailPage.vue (conversacionUrl): se navega por
// display_id (el id de conversacion que expone Chatwoot), nunca por el id de
// base de datos -- "Ver caso" abre la conversacion real, no un modal.
const conversacionUrlDe = fila =>
  fila.conversation_display_id
    ? {
        name: 'inbox_conversation',
        params: {
          accountId: route.params.accountId,
          conversation_id: fila.conversation_display_id,
        },
      }
    : null;
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Filtros (mismo agrupamiento del mockup v12) -->
    <div class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1">
      <div class="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
        <div
          v-for="filtro in selectFiltrosPrincipales"
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
      <div class="grid gap-3 mt-3 md:grid-cols-[1fr_1fr_auto] md:items-end">
        <div class="min-w-0 space-y-1.5">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('HELIC3_INDICADORES.FILTERS.PRODUCT') }}
          </label>
          <Input
            v-model="filtros.producto"
            :placeholder="t('HELIC3_INDICADORES.FILTERS.PRODUCT_PLACEHOLDER')"
          />
        </div>
        <div class="min-w-0 space-y-1.5">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ detalleFiltro.label }}
          </label>
          <Select
            v-model="filtros[detalleFiltro.clave]"
            :options="detalleFiltro.opciones"
            :aria-label="detalleFiltro.label"
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
          class="grid grid-cols-2 divide-x divide-y divide-n-weak rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 md:grid-cols-3 xl:grid-cols-6 md:divide-y-0 overflow-hidden"
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

        <!-- Detalle mensual: tabla + gráfica (mockup v12, "Detalle mensual" / "Recuento vs. ratio") -->
        <div class="grid grid-cols-1 gap-3 xl:grid-cols-[1.7fr_1fr]">
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-x-auto"
          >
            <div class="flex items-start justify-between">
              <div>
                <p class="font-semibold text-n-slate-12">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.MONTHLY') }}
                </p>
                <p class="mt-1 mb-3 text-xs text-n-slate-11">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.MONTHLY_SUBTITLE') }}
                </p>
              </div>
              <Button
                icon="i-lucide-download"
                variant="ghost"
                color="slate"
                size="xs"
                :is-loading="descargando.mensual"
                :title="t('HELIC3_INDICADORES.DOWNLOAD')"
                @click="descargarCsv('mensual')"
              />
            </div>
            <table class="w-full min-w-[28rem] text-sm">
              <thead class="text-xs text-n-slate-11">
                <tr>
                  <th class="px-3 py-2 text-left font-medium">
                    {{ t('HELIC3_INDICADORES.FILTERS.MONTH') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.GARANTIAS.COUNT') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_SOLVED') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_IN_PROGRESS') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="fila in datos.mensual"
                  :key="fila.periodo"
                  class="border-t border-n-weak"
                >
                  <td class="px-3 py-2">
                    <button
                      type="button"
                      class="hover:text-n-brand"
                      :class="
                        filtros.anio == fila.periodo.split('-')[0] &&
                        filtros.mes == fila.periodo.split('-')[1]
                          ? 'text-n-brand font-medium'
                          : 'text-n-slate-11'
                      "
                      @click="seleccionarPeriodo(fila.periodo)"
                    >
                      {{ fila.periodo }}
                    </button>
                  </td>
                  <td
                    class="px-3 py-2 text-right font-medium tabular-nums text-n-slate-12"
                  >
                    {{ fila.cantidad }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-teal-11">
                    {{ fila.solucionadas }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-amber-11">
                    {{ fila.en_proceso }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.GARANTIAS.MONTHLY_CHART') }}
            </p>
            <p class="mt-1 mb-2 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.MONTHLY_SUBTITLE') }}
            </p>
            <ComboBarLineChart
              v-if="datos.mensual.length"
              :categories="categoriasMensual"
              :bar-data="cantidadMensual"
              :bar-label="t('HELIC3_INDICADORES.GARANTIAS.COUNT')"
              :line-data="porcentajeSolucionadasMensual"
              :line-label="t('HELIC3_INDICADORES.GARANTIAS.RESOLVED_RATE')"
              :height="ALTURA_GRAFICA"
              :aria-label="t('HELIC3_INDICADORES.GARANTIAS.MONTHLY_CHART')"
            />
          </div>
        </div>

        <!-- Detalle trimestral: tabla a todo el ancho (mockup v12) -->
        <div
          class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-x-auto"
        >
          <div class="flex items-start justify-between">
            <div>
              <p class="font-semibold text-n-slate-12">
                {{ t('HELIC3_INDICADORES.GARANTIAS.QUARTERLY') }}
              </p>
              <p class="mt-1 mb-3 text-xs text-n-slate-11">
                {{ t('HELIC3_INDICADORES.GARANTIAS.QUARTERLY_SUBTITLE') }}
              </p>
            </div>
            <Button
              icon="i-lucide-download"
              variant="ghost"
              color="slate"
              size="xs"
              :is-loading="descargando.trimestral"
              :title="t('HELIC3_INDICADORES.DOWNLOAD')"
              @click="descargarCsv('trimestral')"
            />
          </div>
          <table class="w-full min-w-[28rem] text-sm">
            <thead class="text-xs text-n-slate-11">
              <tr>
                <th class="px-3 py-2 text-left font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.QUARTER_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.COUNT') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_SOLVED') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_IN_PROGRESS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="fila in datos.trimestral"
                :key="fila.periodo"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2">
                  <button
                    type="button"
                    class="hover:text-n-brand"
                    :class="
                      trimestreSeleccionado === fila.periodo
                        ? 'text-n-brand font-medium'
                        : 'text-n-slate-11'
                    "
                    @click="seleccionarTrimestre(fila.periodo)"
                  >
                    {{ fila.periodo }}
                  </button>
                </td>
                <td
                  class="px-3 py-2 text-right font-medium tabular-nums text-n-slate-12"
                >
                  {{ fila.cantidad }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-teal-11">
                  {{ fila.solucionadas }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-amber-11">
                  {{ fila.en_proceso }}
                </td>
              </tr>
            </tbody>
          </table>

          <!-- Detalle del trimestre elegido: info + grafica de sus meses
          (mockup v12). Se calcula en el cliente, sin pedir nada nuevo al
          backend -- el detalle mensual ya esta completo en memoria. -->
          <div
            v-if="trimestreSeleccionado && filaTrimestreSeleccionada"
            class="p-4 mt-4 rounded-xl bg-n-solid-2"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="text-sm font-medium text-n-slate-12">
                {{
                  t('HELIC3_INDICADORES.GARANTIAS.QUARTER_DETAIL_TITLE', {
                    trimestre: trimestreSeleccionado,
                  })
                }}
              </p>
              <Button
                icon="i-lucide-x"
                variant="ghost"
                color="slate"
                size="xs"
                @click="trimestreSeleccionado = null"
              />
            </div>
            <div class="flex flex-wrap gap-6 mt-2 text-xs text-n-slate-11">
              <span>
                {{ t('HELIC3_INDICADORES.GARANTIAS.COUNT') }}:
                <strong class="text-n-slate-12">{{
                  filaTrimestreSeleccionada.cantidad
                }}</strong>
              </span>
              <span>
                {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_SOLVED') }}:
                <strong class="text-n-teal-11">{{
                  filaTrimestreSeleccionada.solucionadas
                }}</strong>
              </span>
              <span>
                {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_IN_PROGRESS') }}:
                <strong class="text-n-amber-11">{{
                  filaTrimestreSeleccionada.en_proceso
                }}</strong>
              </span>
            </div>
            <ComboBarLineChart
              v-if="mesesTrimestreSeleccionado.length"
              class="mt-4"
              :categories="categoriasTrimestre"
              :bar-data="cantidadTrimestre"
              :bar-label="t('HELIC3_INDICADORES.GARANTIAS.COUNT')"
              :line-data="porcentajeSolucionadasTrimestre"
              :line-label="t('HELIC3_INDICADORES.GARANTIAS.RESOLVED_RATE')"
              :height="180"
              :aria-label="
                t('HELIC3_INDICADORES.GARANTIAS.QUARTER_DETAIL_TITLE', {
                  trimestre: trimestreSeleccionado,
                })
              "
            />
          </div>
        </div>

        <!-- Por ciudad: tabla + comparativo de barras (mockup v12, "Centro de operacion") -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-[1.4fr_1fr]">
          <table
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption class="p-3 caption-top">
              <div class="flex items-center justify-between">
                <span class="font-semibold text-left text-n-slate-12">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.BY_CITY') }}
                </span>
                <Button
                  icon="i-lucide-download"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :is-loading="descargando.por_ciudad"
                  :title="t('HELIC3_INDICADORES.DOWNLOAD')"
                  @click="descargarCsv('por_ciudad')"
                />
              </div>
            </caption>
            <thead class="text-xs text-n-slate-11">
              <tr>
                <th class="px-3 py-2 text-left font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.BY_CITY_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_TOTAL') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_INVOICES') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.KPI_RATIO') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="fila in datos.por_ciudad"
                :key="fila.etiqueta"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2">
                  <button
                    type="button"
                    class="hover:text-n-brand"
                    :class="
                      filtros.cobertura_ciudad_id == fila.valor
                        ? 'text-n-brand font-medium'
                        : 'text-n-slate-11'
                    "
                    :disabled="!fila.valor"
                    @click="seleccionarCiudad(fila.valor)"
                  >
                    {{ etiquetaDe('BY_CITY', fila.etiqueta) }}
                  </button>
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.cantidad }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.facturas }}
                </td>
                <td
                  class="px-3 py-2 font-medium text-right tabular-nums text-n-slate-12"
                >
                  {{ fila.ratio }}%
                </td>
              </tr>
            </tbody>
          </table>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.GARANTIAS.RATIO_CHART') }}
            </p>
            <p class="mt-1 mb-3 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.GARANTIAS.BY_CITY_CHART_SUBTITLE') }}
            </p>
            <div class="space-y-3">
              <button
                v-for="fila in datos.por_ciudad"
                :key="fila.etiqueta"
                type="button"
                class="block w-full text-start"
                :disabled="!fila.valor"
                @click="seleccionarCiudad(fila.valor)"
              >
                <div
                  class="flex items-center justify-between gap-3 text-xs"
                  :class="
                    filtros.cobertura_ciudad_id == fila.valor
                      ? 'text-n-brand font-medium'
                      : 'text-n-slate-11'
                  "
                >
                  <span class="truncate">
                    {{ etiquetaDe('BY_CITY', fila.etiqueta) }}
                  </span>
                  <span class="tabular-nums shrink-0">{{ fila.ratio }}%</span>
                </div>
                <div class="mt-1.5 h-2 rounded-full bg-n-slate-4">
                  <div
                    class="h-2 rounded-full bg-n-blue-9"
                    :style="{ width: `${anchoBarra(fila.ratio)}%` }"
                  />
                </div>
              </button>
            </div>
          </div>
        </div>

        <!-- Resto de desgloses -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <table
            v-for="seccion in [
              {
                titulo: 'BY_MOTIVE',
                clave: 'por_motivo',
                filas: datos.por_motivo,
              },
              {
                titulo: 'BY_DETAIL',
                clave: 'por_detalle',
                filas: datos.por_detalle,
              },
              {
                titulo: 'BY_STAGE',
                clave: 'por_proceso',
                filas: datos.por_proceso,
              },
              {
                titulo: 'BY_PRODUCT',
                clave: 'por_producto',
                filas: datos.por_producto,
              },
            ]"
            :key="seccion.titulo"
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption class="p-3 caption-top">
              <div class="flex items-center justify-between">
                <span class="font-semibold text-left text-n-slate-12">
                  {{ t(`HELIC3_INDICADORES.GARANTIAS.${seccion.titulo}`) }}
                </span>
                <Button
                  icon="i-lucide-download"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :is-loading="descargando[seccion.clave]"
                  :title="t('HELIC3_INDICADORES.DOWNLOAD')"
                  @click="descargarCsv(seccion.clave)"
                />
              </div>
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

        <!-- Detalle de clientes y casos (mockup v12): paginado, ordenado por
        urgencia (vencidos primero, solucionados al final). "Ver caso" abre la
        conversacion real, no un modal. -->
        <div
          class="rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-hidden"
        >
          <div
            class="flex items-start justify-between gap-3 px-4 py-4 border-b border-n-weak"
          >
            <div>
              <p class="font-semibold text-n-slate-12">
                {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.TITLE') }}
              </p>
              <p class="mt-1 text-xs text-n-slate-11">
                {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.SUBTITLE') }}
              </p>
            </div>
          </div>
          <div v-if="cargandoCasos && !casos" class="flex justify-center py-8">
            <Spinner :size="24" />
          </div>
          <template v-else-if="casos">
            <div class="overflow-x-auto">
              <table class="w-full min-w-[48rem] text-sm">
                <thead class="text-xs text-n-slate-11">
                  <tr>
                    <th class="px-4 py-2 text-left font-medium">
                      {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.COL_CLIENT') }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.COL_CENTER') }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.COL_STAGE') }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.COL_PROCESS') }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.COL_DUE') }}
                    </th>
                    <th class="px-4 py-2" />
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="fila in casos.casos"
                    :key="fila.id"
                    class="border-t border-n-weak"
                  >
                    <td class="px-4 py-3">
                      <span class="text-n-brand">
                        #{{ fila.numero_radicado }}
                      </span>
                      <span class="block mt-0.5 text-n-slate-12">
                        {{
                          fila.cliente ||
                          t('HELIC3_INDICADORES.GARANTIAS.CASES.NO_CLIENT')
                        }}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-n-slate-11">
                      {{ fila.centro_operacion || '—' }}
                    </td>
                    <td class="px-4 py-3 text-n-slate-11">
                      {{
                        t(
                          `HELIC3_INDICADORES.GARANTIAS.CASES.STAGE_${fila.etapa.toUpperCase()}`
                        )
                      }}
                    </td>
                    <td class="px-4 py-3 text-n-slate-11">
                      {{ fila.proceso || '—' }}
                    </td>
                    <td class="px-4 py-3">
                      <span :class="colorVencimiento(fila.vencimiento.estado)">
                        {{ textoVencimiento(fila) }}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-right whitespace-nowrap">
                      <router-link
                        v-if="conversacionUrlDe(fila)"
                        :to="conversacionUrlDe(fila)"
                        class="text-n-brand hover:underline"
                      >
                        {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.VIEW_CASE') }}
                      </router-link>
                    </td>
                  </tr>
                  <tr v-if="!casos.casos.length">
                    <td
                      colspan="6"
                      class="px-4 py-8 text-sm text-center text-n-slate-11"
                    >
                      {{ t('HELIC3_INDICADORES.GARANTIAS.CASES.EMPTY') }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div
              class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-t border-n-weak text-xs text-n-slate-11"
            >
              <p>
                {{
                  t('HELIC3_INDICADORES.GARANTIAS.CASES.TOTAL', {
                    total: casos.total,
                  })
                }}
              </p>
              <div class="flex items-center gap-3">
                <Button
                  :label="t('HELIC3_INDICADORES.GARANTIAS.CASES.PREV')"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :disabled="casos.pagina <= 1 || cargandoCasos"
                  @click="irAPagina(casos.pagina - 1)"
                />
                <span>{{ casos.pagina }} / {{ casos.paginas }}</span>
                <Button
                  :label="t('HELIC3_INDICADORES.GARANTIAS.CASES.NEXT')"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :disabled="casos.pagina >= casos.paginas || cargandoCasos"
                  @click="irAPagina(casos.pagina + 1)"
                />
              </div>
            </div>
          </template>
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
