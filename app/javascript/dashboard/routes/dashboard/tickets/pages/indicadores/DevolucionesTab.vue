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
import MultiSeriesBarChart from 'dashboard/components-next/helic3/MultiSeriesBarChart.vue';
import { useIndicadoresStore } from 'dashboard/store/helic3/indicadores';
import IndicadoresAPI from 'dashboard/api/helic3/indicadores';
import { downloadBlobResponse } from 'dashboard/helper/helic3/downloadHelper';

// IND-06: tercera pestaña de Indicadores. Devolucion es un expediente
// hermano de Garantia (misma tabla de servicio, mismo reloj de 30 dias
// habiles); el detalle tipificado y el proceso reusan los catalogos ya
// existentes de Garantia (motivos_devolucion es el unico catalogo propio).
const { t, locale } = useI18n();
const route = useRoute();
const store = useStore();
const indicadoresStore = useIndicadoresStore();

const catalogos = useMapGetter('tickets/getCatalogos');
const datos = computed(() => indicadoresStore.getDevoluciones);
const cargando = computed(
  () => indicadoresStore.getUIFlags.isFetchingDevoluciones
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
  motivo_devolucion_id: '',
  detalle_tipificado_id: '',
  proceso_id: '',
  producto: '',
});

const todos = () => ({ value: '', label: t('HELIC3_INDICADORES.FILTERS.ALL') });
const anioOptions = computed(() => [
  todos(),
  ...ANIOS.map(anio => ({ value: anio, label: String(anio) })),
]);

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
const motivoOptions = opcionesDe('motivos_devolucion');
const detalleOptions = opcionesDe('detalles_tipificados');
const procesoOptions = opcionesDe('procesos_garantia');

// Mismo agrupamiento que GarantiasTab.vue (mockup v12): año/mes/ciudad/motivo/
// etapa en una fila, detalle tipificado junto al producto en la segunda.
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
    clave: 'motivo_devolucion_id',
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
    await indicadoresStore.fetchDevoluciones(parametrosActuales());
  } catch (error) {
    huboError.value = true;
    useAlert(t('HELIC3_INDICADORES.ERROR'));
  }
};

// Detalle de clientes y casos (mismo patron de GarantiasTab.vue): paginado
// aparte de los agregados de arriba, con los mismos filtros.
const casos = computed(() => indicadoresStore.getDevolucionesCasos);
const cargandoCasos = computed(
  () => indicadoresStore.getUIFlags.isFetchingDevolucionesCasos
);
const casosPagina = ref(1);
const cargarCasos = async () => {
  try {
    await indicadoresStore.fetchDevolucionesCasos(
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
    const response = await IndicadoresAPI.devolucionesCsv(
      seccion,
      parametrosActuales()
    );
    downloadBlobResponse(response, `indicadores-devoluciones-${seccion}.csv`);
  } catch (error) {
    useAlert(t('HELIC3_INDICADORES.DOWNLOAD_ERROR'));
  } finally {
    descargando[seccion] = false;
  }
};

// Se despliega al hacer click en un trimestre de "Detalle trimestral"/
// "Motivo por trimestre"/"Detalle tipificado por trimestre" (ver mas abajo);
// declarados aqui para que limpiarFiltros pueda cerrarlos sin dejar un
// trimestre viejo abierto tras limpiar filtros.
const trimestreSeleccionado = ref(null);
const trimestreMotivoSeleccionado = ref(null);
const trimestreDetalleSeleccionado = ref(null);

// Mismo criterio del mockup (data-action="stats-reset"): un solo click
// vuelve todo a su estado inicial -- filtros y el trimestre desplegado, no
// solo los selectores.
const limpiarFiltros = () => {
  Object.keys(filtros).forEach(clave => {
    filtros[clave] = '';
  });
  trimestreSeleccionado.value = null;
  trimestreMotivoSeleccionado.value = null;
  trimestreDetalleSeleccionado.value = null;
  casosPagina.value = 1;
};

// Mismo ajuste de interactividad que GarantiasTab.vue (mockup v12): click en
// un mes o en una tienda filtra el resto del tablero por ese periodo/tienda.
const seleccionarPeriodo = periodo => {
  const [anio, mes] = periodo.split('-');
  filtros.anio = Number(anio);
  filtros.mes = Number(mes);
};

const seleccionarCiudad = cobertura_ciudad_id => {
  if (!cobertura_ciudad_id) return;
  filtros.cobertura_ciudad_id = cobertura_ciudad_id;
};

// Paridad con el Dash CX: "Producto" es un filtro global mas (como ciudad),
// no una ventana aparte -- clickear un producto filtra todo el tablero
// (tarjetas, mensual, motivo, detalle) a ese producto exacto.
const seleccionarProducto = nombre => {
  if (!nombre) return;
  filtros.producto = nombre;
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

watch(
  () => [
    filtros.anio,
    filtros.mes,
    filtros.cobertura_ciudad_id,
    filtros.motivo_devolucion_id,
    filtros.detalle_tipificado_id,
    filtros.proceso_id,
  ],
  cargarTodo
);

let debounceBusqueda = null;
watch(
  () => filtros.producto,
  () => {
    clearTimeout(debounceBusqueda);
    debounceBusqueda = setTimeout(cargarTodo, DEBOUNCE_BUSQUEDA_MS);
  }
);

const sinDatos = computed(
  () => !!datos.value && datos.value.kpis.devoluciones === 0
);

const kpiCards = computed(() => [
  {
    label: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_TOTAL'),
    valor: datos.value?.kpis.devoluciones,
    descripcion: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_TOTAL_DESC'),
    color: 'text-n-slate-12',
  },
  {
    label: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_SOLVED'),
    valor: datos.value?.kpis.solucionadas,
    descripcion: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_SOLVED_DESC'),
    color: 'text-n-teal-11',
  },
  {
    label: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_IN_PROGRESS'),
    valor: datos.value?.kpis.en_proceso,
    descripcion: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_IN_PROGRESS_DESC'),
    color: 'text-n-amber-11',
  },
  {
    label: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_PRODUCTS'),
    valor: datos.value?.kpis.productos,
    descripcion: t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_PRODUCTS_DESC'),
    color: 'text-n-slate-12',
  },
]);

// "Recuento vs. ratio" (mockup v12): la linea muestra % solucionadas en vez
// de devoluciones/facturas -- ese ratio sigue bloqueado por el modelo de
// datos de Facturas (IND-04, sin definir). Mismo criterio de GarantiasTab.vue.
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

// Detalle trimestral: click en un trimestre despliega sus meses (mismo
// patron de GarantiasTab.vue). Sin pedir nada al backend: el detalle
// mensual ya esta completo en memoria.
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

// Paridad con el Dash CX ("Devoluciones por motivo"/"Detalle tipificado"):
// matriz motivo/detalle x trimestre con grafico de colores, donde clickear
// un trimestre lo despliega por mes -- igual que "Detalle trimestral" de
// arriba, pero la fuente es motivo_por_mes/detalle_por_mes en vez de
// mensual, y el trimestre es solo T1..T4 (sin anio: ya viene agregado del
// backend, igual que el motivo_por_trimestre de PQR).
const TRIMESTRES_NUMERO = { T1: 1, T2: 2, T3: 3, T4: 4 };

const alternarTrimestre = (seleccionadoRef, trimestre) => {
  seleccionadoRef.value =
    seleccionadoRef.value === trimestre ? null : trimestre;
};
const seleccionarTrimestreMotivo = trimestre =>
  alternarTrimestre(trimestreMotivoSeleccionado, trimestre);
const seleccionarTrimestreDetalle = trimestre =>
  alternarTrimestre(trimestreDetalleSeleccionado, trimestre);

const seriesPorTrimestre = (filas, campo, etiquetaSinDato) =>
  filas.map(fila => ({
    nombre: fila[campo] ?? etiquetaSinDato,
    valores: [fila.t1, fila.t2, fila.t3, fila.t4],
  }));

const trimestreDeMes = periodo =>
  Math.floor((Number(periodo.split('-')[1]) - 1) / 3) + 1;

// Pivotea {motivo/detalle, periodo, cantidad} (lo que trae *_por_mes) a
// series por nombre, recortadas al trimestre clickeado -- el periodo trae el
// anio (p. ej. "2026-04"), asi que si el filtro de Año esta en "Todos" cada
// anio del trimestre aparece como su propia columna en vez de sumarse.
const pivotPorMes = (filas, campo, trimestre, etiquetaSinDato) => {
  const delTrimestre = filas.filter(
    fila => TRIMESTRES_NUMERO[trimestre] === trimestreDeMes(fila.periodo)
  );
  const categorias = [
    ...new Set(delTrimestre.map(fila => fila.periodo)),
  ].sort();
  const nombres = [
    ...new Set(delTrimestre.map(fila => fila[campo] ?? etiquetaSinDato)),
  ];
  const series = nombres.map(nombre => ({
    nombre,
    valores: categorias.map(
      periodo =>
        delTrimestre.find(
          fila =>
            (fila[campo] ?? etiquetaSinDato) === nombre &&
            fila.periodo === periodo
        )?.cantidad || 0
    ),
  }));
  return { categorias, series };
};

const seriesMotivoTrimestre = computed(() =>
  seriesPorTrimestre(
    datos.value?.motivo_por_trimestre || [],
    'motivo',
    t('HELIC3_INDICADORES.DEVOLUCIONES.NO_MOTIVE')
  )
);
const motivoPorMesPivot = computed(() =>
  trimestreMotivoSeleccionado.value
    ? pivotPorMes(
        datos.value?.motivo_por_mes || [],
        'motivo',
        trimestreMotivoSeleccionado.value,
        t('HELIC3_INDICADORES.DEVOLUCIONES.NO_MOTIVE')
      )
    : { categorias: [], series: [] }
);

const seriesDetalleTrimestre = computed(() =>
  seriesPorTrimestre(
    datos.value?.detalle_por_trimestre || [],
    'detalle',
    t('HELIC3_INDICADORES.DEVOLUCIONES.NO_DETAIL')
  )
);
const detallePorMesPivot = computed(() =>
  trimestreDetalleSeleccionado.value
    ? pivotPorMes(
        datos.value?.detalle_por_mes || [],
        'detalle',
        trimestreDetalleSeleccionado.value,
        t('HELIC3_INDICADORES.DEVOLUCIONES.NO_DETAIL')
      )
    : { categorias: [], series: [] }
);

const ETIQUETA_SIN_DATO = {
  BY_CITY: 'NO_CITY',
  BY_MOTIVE: 'NO_MOTIVE',
  BY_DETAIL: 'NO_DETAIL',
  BY_STAGE: 'NO_STAGE',
};
const etiquetaDe = (seccionTitulo, etiqueta) => {
  if (etiqueta !== null && etiqueta !== undefined) return etiqueta;
  const clave = ETIQUETA_SIN_DATO[seccionTitulo];
  return clave ? t(`HELIC3_INDICADORES.DEVOLUCIONES.${clave}`) : etiqueta;
};

const porCiudadConNombre = computed(() =>
  (datos.value?.por_ciudad || []).map(fila => ({
    ...fila,
    nombre: etiquetaDe('BY_CITY', fila.etiqueta),
  }))
);
const maxPorCiudad = computed(() =>
  Math.max(1, ...porCiudadConNombre.value.map(fila => fila.cantidad))
);
const anchoBarra = cantidad => `${(cantidad / maxPorCiudad.value) * 100}%`;

const maxPorProducto = computed(() =>
  Math.max(1, ...(datos.value?.por_producto || []).map(fila => fila.cantidad))
);
const anchoBarraProducto = cantidad =>
  `${(cantidad / maxPorProducto.value) * 100}%`;

// "Detalle de clientes y casos" (mismo patron de GarantiasTab.vue): el
// semaforo ya viene calculado del backend (PLZ-01), aqui solo se traduce a
// color + texto.
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
    return t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.DUE_DONE');
  }
  const dias = fila.vencimiento.saldo_dias_habiles;
  return dias < 0
    ? t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.DUE_OVERDUE', {
        dias: Math.abs(dias),
      })
    : t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.DUE_REMAINING', { dias });
};

// Mismo patron de GarantiasTab.vue/PqrDetailPage.vue: se navega por
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
    <!-- Filtros (mismo agrupamiento que GarantiasTab.vue / mockup v12) -->
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

        <!-- Detalle mensual: tabla + grafica -->
        <div class="grid grid-cols-1 gap-3 xl:grid-cols-[1.7fr_1fr]">
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-x-auto"
          >
            <div class="flex items-start justify-between">
              <div>
                <p class="font-semibold text-n-slate-12">
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.MONTHLY') }}
                </p>
                <p class="mt-1 mb-3 text-xs text-n-slate-11">
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.MONTHLY_SUBTITLE') }}
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
                    {{ t('HELIC3_INDICADORES.DEVOLUCIONES.COUNT') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_SOLVED') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_IN_PROGRESS') }}
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
              {{ t('HELIC3_INDICADORES.DEVOLUCIONES.MONTHLY_CHART') }}
            </p>
            <p class="mt-1 mb-2 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.DEVOLUCIONES.MONTHLY_SUBTITLE') }}
            </p>
            <ComboBarLineChart
              v-if="datos.mensual.length"
              :categories="categoriasMensual"
              :bar-data="cantidadMensual"
              :bar-label="t('HELIC3_INDICADORES.DEVOLUCIONES.COUNT')"
              :line-data="porcentajeSolucionadasMensual"
              :line-label="t('HELIC3_INDICADORES.DEVOLUCIONES.RESOLVED_RATE')"
              :height="ALTURA_GRAFICA"
              :aria-label="t('HELIC3_INDICADORES.DEVOLUCIONES.MONTHLY_CHART')"
            />
          </div>
        </div>

        <!-- Detalle trimestral -->
        <div
          class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-x-auto"
        >
          <div class="flex items-start justify-between">
            <div>
              <p class="font-semibold text-n-slate-12">
                {{ t('HELIC3_INDICADORES.DEVOLUCIONES.QUARTERLY') }}
              </p>
              <p class="mt-1 mb-3 text-xs text-n-slate-11">
                {{ t('HELIC3_INDICADORES.DEVOLUCIONES.QUARTERLY_SUBTITLE') }}
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
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.QUARTER_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.COUNT') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_SOLVED') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_IN_PROGRESS') }}
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
          (mismo patron de GarantiasTab.vue). Se calcula en el cliente, sin
          pedir nada nuevo al backend. -->
          <div
            v-if="trimestreSeleccionado && filaTrimestreSeleccionada"
            class="p-4 mt-4 rounded-xl bg-n-solid-2"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="text-sm font-medium text-n-slate-12">
                {{
                  t('HELIC3_INDICADORES.DEVOLUCIONES.QUARTER_DETAIL_TITLE', {
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
                {{ t('HELIC3_INDICADORES.DEVOLUCIONES.COUNT') }}:
                <strong class="text-n-slate-12">{{
                  filaTrimestreSeleccionada.cantidad
                }}</strong>
              </span>
              <span>
                {{ t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_SOLVED') }}:
                <strong class="text-n-teal-11">{{
                  filaTrimestreSeleccionada.solucionadas
                }}</strong>
              </span>
              <span>
                {{ t('HELIC3_INDICADORES.DEVOLUCIONES.KPI_IN_PROGRESS') }}:
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
              :bar-label="t('HELIC3_INDICADORES.DEVOLUCIONES.COUNT')"
              :line-data="porcentajeSolucionadasTrimestre"
              :line-label="t('HELIC3_INDICADORES.DEVOLUCIONES.RESOLVED_RATE')"
              :height="180"
              :aria-label="
                t('HELIC3_INDICADORES.DEVOLUCIONES.QUARTER_DETAIL_TITLE', {
                  trimestre: trimestreSeleccionado,
                })
              "
            />
          </div>
        </div>

        <!-- Por ciudad: tabla + comparativo -->
        <div class="grid grid-cols-1 gap-3 xl:grid-cols-[1.4fr_1fr]">
          <table
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption class="p-3 caption-top">
              <div class="flex items-center justify-between">
                <span class="font-medium text-left text-n-slate-12">
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.BY_CITY') }}
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
                <td class="px-3 py-2 font-medium text-right text-n-slate-12">
                  {{ fila.cantidad }}
                </td>
              </tr>
            </tbody>
          </table>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.DEVOLUCIONES.BY_CITY_CHART') }}
            </p>
            <p class="mt-1 mb-3 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.DEVOLUCIONES.BY_CITY_CHART_SUBTITLE') }}
            </p>
            <ul class="space-y-2">
              <li
                v-for="fila in porCiudadConNombre"
                :key="fila.nombre"
                class="text-sm"
              >
                <button
                  type="button"
                  class="block w-full text-start"
                  :disabled="!fila.valor"
                  @click="seleccionarCiudad(fila.valor)"
                >
                  <div
                    class="flex items-baseline justify-between mb-1"
                    :class="
                      filtros.cobertura_ciudad_id == fila.valor
                        ? 'text-n-brand font-medium'
                        : ''
                    "
                  >
                    <span
                      :class="
                        filtros.cobertura_ciudad_id != fila.valor
                          ? 'text-n-slate-11'
                          : ''
                      "
                    >
                      {{ fila.nombre }}
                    </span>
                    <span class="font-medium tabular-nums text-n-slate-12">
                      {{ fila.cantidad }}
                    </span>
                  </div>
                  <div class="h-1.5 rounded-full bg-n-slate-4 overflow-hidden">
                    <div
                      class="h-full rounded-full bg-n-blue-9"
                      :style="{ width: anchoBarra(fila.cantidad) }"
                    />
                  </div>
                </button>
              </li>
            </ul>
          </div>
        </div>

        <!-- Por producto: tabla + comparativo (paridad con el Dash CX, donde
        "Producto" es un filtro global mas -- clickear un producto filtra
        todo el tablero, igual que ciudad). -->
        <div class="grid grid-cols-1 gap-3 xl:grid-cols-[1.4fr_1fr]">
          <table
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption class="p-3 caption-top">
              <div class="flex items-center justify-between">
                <span class="font-medium text-left text-n-slate-12">
                  {{ t('HELIC3_INDICADORES.DEVOLUCIONES.BY_PRODUCT') }}
                </span>
                <Button
                  icon="i-lucide-download"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :is-loading="descargando.por_producto"
                  :title="t('HELIC3_INDICADORES.DOWNLOAD')"
                  @click="descargarCsv('por_producto')"
                />
              </div>
            </caption>
            <tbody>
              <tr
                v-for="fila in datos.por_producto"
                :key="fila.etiqueta"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2">
                  <button
                    type="button"
                    class="hover:text-n-brand"
                    :class="
                      filtros.producto === fila.etiqueta
                        ? 'text-n-brand font-medium'
                        : 'text-n-slate-11'
                    "
                    @click="seleccionarProducto(fila.etiqueta)"
                  >
                    {{ fila.etiqueta }}
                  </button>
                </td>
                <td class="px-3 py-2 font-medium text-right text-n-slate-12">
                  {{ fila.cantidad }}
                </td>
              </tr>
            </tbody>
          </table>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.DEVOLUCIONES.BY_PRODUCT_CHART') }}
            </p>
            <p class="mt-1 mb-3 text-xs text-n-slate-11">
              {{
                t('HELIC3_INDICADORES.DEVOLUCIONES.BY_PRODUCT_CHART_SUBTITLE')
              }}
            </p>
            <ul class="space-y-2">
              <li
                v-for="fila in datos.por_producto"
                :key="fila.etiqueta"
                class="text-sm"
              >
                <button
                  type="button"
                  class="block w-full text-start"
                  @click="seleccionarProducto(fila.etiqueta)"
                >
                  <div
                    class="flex items-baseline justify-between mb-1 gap-2"
                    :class="
                      filtros.producto === fila.etiqueta
                        ? 'text-n-brand font-medium'
                        : ''
                    "
                  >
                    <span
                      class="truncate"
                      :class="
                        filtros.producto !== fila.etiqueta
                          ? 'text-n-slate-11'
                          : ''
                      "
                    >
                      {{ fila.etiqueta }}
                    </span>
                    <span class="font-medium tabular-nums text-n-slate-12">
                      {{ fila.cantidad }}
                    </span>
                  </div>
                  <div class="h-1.5 rounded-full bg-n-slate-4 overflow-hidden">
                    <div
                      class="h-full rounded-full bg-n-blue-9"
                      :style="{ width: anchoBarraProducto(fila.cantidad) }"
                    />
                  </div>
                </button>
              </li>
            </ul>
          </div>
        </div>

        <!-- Motivo/Detalle por trimestre (paridad con el Dash CX): matriz
        T1-T4 + grafico de colores por motivo/detalle; click en un trimestre
        lo despliega por mes, igual que "Detalle trimestral" de arriba. -->
        <div
          v-for="bloque in [
            {
              titulo: 'MOTIVE_QUARTER',
              subtitulo: 'MOTIVE_QUARTER_SUBTITLE',
              columna: 'MOTIVE_COLUMN',
              clave: 'motivo_por_trimestre',
              campo: 'motivo',
              filas: datos.motivo_por_trimestre,
              series: seriesMotivoTrimestre,
              seleccionado: trimestreMotivoSeleccionado,
              pivot: motivoPorMesPivot,
              seleccionar: seleccionarTrimestreMotivo,
            },
            {
              titulo: 'DETAIL_QUARTER',
              subtitulo: 'DETAIL_QUARTER_SUBTITLE',
              columna: 'DETAIL_COLUMN',
              clave: 'detalle_por_trimestre',
              campo: 'detalle',
              filas: datos.detalle_por_trimestre,
              series: seriesDetalleTrimestre,
              seleccionado: trimestreDetalleSeleccionado,
              pivot: detallePorMesPivot,
              seleccionar: seleccionarTrimestreDetalle,
            },
          ]"
          :key="bloque.titulo"
          class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="font-semibold text-n-slate-12">
                {{ t(`HELIC3_INDICADORES.DEVOLUCIONES.${bloque.titulo}`) }}
              </p>
              <p class="mt-1 text-xs text-n-slate-11">
                {{ t(`HELIC3_INDICADORES.DEVOLUCIONES.${bloque.subtitulo}`) }}
              </p>
            </div>
            <Button
              icon="i-lucide-download"
              variant="ghost"
              color="slate"
              size="xs"
              :is-loading="descargando[bloque.clave]"
              :title="t('HELIC3_INDICADORES.DOWNLOAD')"
              @click="descargarCsv(bloque.clave)"
            />
          </div>
          <div class="grid grid-cols-1 gap-3 mt-3 xl:grid-cols-[1.4fr_1fr]">
            <div class="overflow-x-auto">
              <table class="w-full min-w-[28rem] text-sm">
                <thead class="text-xs text-n-slate-11">
                  <tr>
                    <th class="px-3 py-2 text-left font-medium">
                      {{
                        t(`HELIC3_INDICADORES.DEVOLUCIONES.${bloque.columna}`)
                      }}
                    </th>
                    <template v-if="!bloque.seleccionado">
                      <th
                        v-for="columna in ['T1', 'T2', 'T3', 'T4']"
                        :key="columna"
                        class="px-3 py-2 text-right font-medium"
                      >
                        {{ columna }}
                      </th>
                      <th class="px-3 py-2 text-right font-medium">
                        {{ t('HELIC3_INDICADORES.DEVOLUCIONES.TOTAL_COLUMN') }}
                      </th>
                    </template>
                    <th
                      v-for="periodo in bloque.seleccionado
                        ? bloque.pivot.categorias
                        : []"
                      :key="periodo"
                      class="px-3 py-2 text-right font-medium"
                    >
                      {{ periodo }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <template v-if="!bloque.seleccionado">
                    <tr
                      v-for="fila in bloque.filas"
                      :key="fila[bloque.campo] ?? 'sin-dato'"
                      class="border-t border-n-weak"
                    >
                      <td class="px-3 py-2 text-n-slate-11">
                        {{
                          etiquetaDe(
                            bloque.titulo === 'MOTIVE_QUARTER'
                              ? 'BY_MOTIVE'
                              : 'BY_DETAIL',
                            fila[bloque.campo]
                          )
                        }}
                      </td>
                      <td
                        class="px-3 py-2 text-right tabular-nums text-n-slate-11"
                      >
                        {{ fila.t1 }}
                      </td>
                      <td
                        class="px-3 py-2 text-right tabular-nums text-n-slate-11"
                      >
                        {{ fila.t2 }}
                      </td>
                      <td
                        class="px-3 py-2 text-right tabular-nums text-n-slate-11"
                      >
                        {{ fila.t3 }}
                      </td>
                      <td
                        class="px-3 py-2 text-right tabular-nums text-n-slate-11"
                      >
                        {{ fila.t4 }}
                      </td>
                      <td
                        class="px-3 py-2 text-right font-medium tabular-nums text-n-slate-12"
                      >
                        {{ fila.total }}
                      </td>
                    </tr>
                  </template>
                  <template v-else>
                    <tr
                      v-for="serie in bloque.pivot.series"
                      :key="serie.nombre"
                      class="border-t border-n-weak"
                    >
                      <td class="px-3 py-2 text-n-slate-11">
                        {{ serie.nombre }}
                      </td>
                      <td
                        v-for="(valor, indice) in serie.valores"
                        :key="indice"
                        class="px-3 py-2 text-right tabular-nums text-n-slate-11"
                      >
                        {{ valor }}
                      </td>
                    </tr>
                  </template>
                </tbody>
              </table>
            </div>
            <div>
              <Button
                v-if="bloque.seleccionado"
                variant="faded"
                color="slate"
                size="xs"
                icon="i-lucide-arrow-left"
                :label="t('HELIC3_INDICADORES.DEVOLUCIONES.BACK_TO_QUARTERS')"
                class="mb-2"
                @click="bloque.seleccionar(bloque.seleccionado)"
              />
              <MultiSeriesBarChart
                :categories="
                  bloque.seleccionado
                    ? bloque.pivot.categorias
                    : ['T1', 'T2', 'T3', 'T4']
                "
                :series="
                  bloque.seleccionado ? bloque.pivot.series : bloque.series
                "
                :selected-category="bloque.seleccionado"
                :aria-label="
                  t(`HELIC3_INDICADORES.DEVOLUCIONES.${bloque.titulo}`)
                "
                @select-category="
                  categoria =>
                    !bloque.seleccionado && bloque.seleccionar(categoria)
                "
              />
            </div>
          </div>
        </div>

        <!-- Otros desgloses -->
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
            ]"
            :key="seccion.titulo"
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption class="p-3 caption-top">
              <div class="flex items-center justify-between">
                <span class="font-medium text-left text-n-slate-12">
                  {{ t(`HELIC3_INDICADORES.DEVOLUCIONES.${seccion.titulo}`) }}
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
                <td class="px-3 py-2 font-medium text-right text-n-slate-12">
                  {{ fila.cantidad }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Detalle de clientes y casos (mismo patron de GarantiasTab.vue):
        paginado, ordenado por urgencia. "Ver caso" abre la conversacion
        real, no un modal. -->
        <div
          class="rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-hidden"
        >
          <div
            class="flex items-start justify-between gap-3 px-4 py-4 border-b border-n-weak"
          >
            <div>
              <p class="font-semibold text-n-slate-12">
                {{ t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.TITLE') }}
              </p>
              <p class="mt-1 text-xs text-n-slate-11">
                {{ t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.SUBTITLE') }}
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
                      {{
                        t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.COL_CLIENT')
                      }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{
                        t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.COL_CENTER')
                      }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{ t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.COL_STAGE') }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{
                        t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.COL_PROCESS')
                      }}
                    </th>
                    <th class="px-4 py-2 text-left font-medium">
                      {{ t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.COL_DUE') }}
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
                          t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.NO_CLIENT')
                        }}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-n-slate-11">
                      {{ fila.centro_operacion || '—' }}
                    </td>
                    <td class="px-4 py-3 text-n-slate-11">
                      {{
                        t(
                          `HELIC3_INDICADORES.DEVOLUCIONES.CASES.STAGE_${fila.etapa.toUpperCase()}`
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
                        {{
                          t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.VIEW_CASE')
                        }}
                      </router-link>
                    </td>
                  </tr>
                  <tr v-if="!casos.casos.length">
                    <td
                      colspan="6"
                      class="px-4 py-8 text-sm text-center text-n-slate-11"
                    >
                      {{ t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.EMPTY') }}
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
                  t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.TOTAL', {
                    total: casos.total,
                  })
                }}
              </p>
              <div class="flex items-center gap-3">
                <Button
                  :label="t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.PREV')"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :disabled="casos.pagina <= 1 || cargandoCasos"
                  @click="irAPagina(casos.pagina - 1)"
                />
                <span>{{ casos.pagina }} / {{ casos.paginas }}</span>
                <Button
                  :label="t('HELIC3_INDICADORES.DEVOLUCIONES.CASES.NEXT')"
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
/* Mismo ajuste de GarantiasTab.vue (revision de Jhan, PR #123): Select.vue es
   upstream puro, no se toca. El ancho se fuerza desde la pagina. */
:deep(.w-fit.relative),
:deep(.w-fit.relative select) {
  width: 100%;
}
</style>
