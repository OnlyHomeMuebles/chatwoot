<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import { useIndicadoresStore } from 'dashboard/store/helic3/indicadores';
import IndicadoresAPI from 'dashboard/api/helic3/indicadores';
import { downloadBlobResponse } from 'dashboard/helper/helic3/downloadHelper';

// IND-02: segunda pestaña de Indicadores. Las PQR que YA estan en el CRM
// (helic3_tickets), con el cumplimiento del plazo legal de 15 dias habiles
// que hoy no se mide en ningun lado. Historico llega con IND-04.
const { t, locale } = useI18n();
const store = useStore();
const indicadoresStore = useIndicadoresStore();

// tickets/getCatalogos ya trae tipos/motivos_pqr (el mismo catalogo que usa
// TicketsPage.vue); agents/getAgents da la lista de responsables posibles.
const catalogos = useMapGetter('tickets/getCatalogos');
const agentes = useMapGetter('agents/getAgents');
const datos = computed(() => indicadoresStore.getPqr);
const cargando = computed(() => indicadoresStore.getUIFlags.isFetchingPqr);

const ANIO_ACTUAL = new Date().getFullYear();
const ANIOS = Array.from({ length: 5 }, (_, i) => ANIO_ACTUAL - i);
const MESES = Array.from({ length: 12 }, (_, i) => i + 1);
const ALTURA_GRAFICA = 240;
const COLUMNAS_TRIMESTRE = [1, 2, 3, 4].map(trimestre => `T${trimestre}`);

const filtros = reactive({
  anio: '',
  mes: '',
  tipo_id: '',
  motivo_pqr_id: '',
  assignee_id: '',
});

const todos = () => ({ value: '', label: t('HELIC3_INDICADORES.FILTERS.ALL') });
const anioOptions = computed(() => [
  todos(),
  ...ANIOS.map(anio => ({ value: anio, label: String(anio) })),
]);

// N4 (mismo ajuste que GarantiasTab.vue): nombres de mes, no 1-12.
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
const tipoOptions = computed(() => [
  todos(),
  ...(catalogos.value.tipos || []).map(fila => ({
    value: fila.id,
    label: fila.nombre,
  })),
]);
const motivoOptions = computed(() => [
  todos(),
  ...(catalogos.value.motivos_pqr || []).map(fila => ({
    value: fila.id,
    label: fila.nombre,
  })),
]);
const responsableOptions = computed(() => [
  todos(),
  ...agentes.value.map(agente => ({ value: agente.id, label: agente.name })),
]);

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
    clave: 'tipo_id',
    label: t('HELIC3_INDICADORES.FILTERS.TYPE'),
    opciones: tipoOptions.value,
  },
  {
    clave: 'motivo_pqr_id',
    label: t('HELIC3_INDICADORES.FILTERS.MOTIVE'),
    opciones: motivoOptions.value,
  },
  {
    clave: 'assignee_id',
    label: t('HELIC3_INDICADORES.FILTERS.RESPONSIBLE'),
    opciones: responsableOptions.value,
  },
]);

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
    await indicadoresStore.fetchPqr(parametrosActuales());
  } catch (error) {
    huboError.value = true;
    useAlert(t('HELIC3_INDICADORES.ERROR'));
  }
};

const descargando = reactive({});
const descargarCsv = async seccion => {
  descargando[seccion] = true;
  try {
    const response = await IndicadoresAPI.pqrCsv(seccion, parametrosActuales());
    downloadBlobResponse(response, `indicadores-pqr-${seccion}.csv`);
  } catch (error) {
    useAlert(t('HELIC3_INDICADORES.DOWNLOAD_ERROR'));
  } finally {
    descargando[seccion] = false;
  }
};

const limpiarFiltros = () => {
  Object.keys(filtros).forEach(clave => {
    filtros[clave] = '';
  });
};

// Mismo ajuste de interactividad que GarantiasTab.vue (mockup v12): click en
// un mes de "Detalle mensual" filtra el resto del tablero por ese periodo.
const seleccionarPeriodo = periodo => {
  const [anio, mes] = periodo.split('-');
  filtros.anio = Number(anio);
  filtros.mes = Number(mes);
};

onMounted(() => {
  store.dispatch('tickets/getCatalogos');
  store.dispatch('agents/get');
  cargar();
});

// pocas filas (GROUP BY): sin debounce ni paginacion en cliente, igual que
// GarantiasTab.vue -- aqui no hay filtro de texto libre que lo justifique.
watch(
  () => [
    filtros.anio,
    filtros.mes,
    filtros.tipo_id,
    filtros.motivo_pqr_id,
    filtros.assignee_id,
  ],
  cargar
);

const sinDatos = computed(
  () => !!datos.value && datos.value.kpis.radicadas === 0
);

const porcentaje = valor =>
  valor === null || valor === undefined ? '—' : `${valor}%`;

const kpiCards = computed(() => [
  {
    label: t('HELIC3_INDICADORES.PQR.KPI_FILED'),
    valor: datos.value?.kpis.radicadas,
    descripcion: t('HELIC3_INDICADORES.PQR.KPI_FILED_DESC'),
    color: 'text-n-slate-12',
  },
  {
    label: t('HELIC3_INDICADORES.PQR.KPI_RESPONDED'),
    valor: datos.value?.kpis.respondidas,
    descripcion: t('HELIC3_INDICADORES.PQR.KPI_RESPONDED_DESC'),
    color: 'text-n-teal-11',
  },
  {
    label: t('HELIC3_INDICADORES.PQR.KPI_PENDING'),
    valor: datos.value?.kpis.pendientes,
    descripcion: t('HELIC3_INDICADORES.PQR.KPI_PENDING_DESC'),
    color: 'text-n-amber-11',
  },
  {
    label: t('HELIC3_INDICADORES.PQR.KPI_RESPONSE_RATE'),
    valor: porcentaje(datos.value?.kpis.pct_respondidas),
    descripcion: t('HELIC3_INDICADORES.PQR.KPI_RESPONSE_RATE_DESC'),
    color: 'text-n-slate-12',
  },
  {
    label: t('HELIC3_INDICADORES.PQR.KPI_ON_TIME'),
    valor: datos.value?.kpis.dentro_plazo,
    descripcion: t('HELIC3_INDICADORES.PQR.KPI_ON_TIME_DESC'),
    color: 'text-n-teal-11',
  },
  {
    label: t('HELIC3_INDICADORES.PQR.KPI_OVERDUE'),
    valor: datos.value?.kpis.vencidas_sin_responder,
    descripcion: t('HELIC3_INDICADORES.PQR.KPI_OVERDUE_DESC'),
    color: 'text-n-ruby-11',
  },
  {
    label: t('HELIC3_INDICADORES.PQR.KPI_COMPLIANCE'),
    valor: porcentaje(datos.value?.kpis.pct_cumplimiento),
    descripcion: t('HELIC3_INDICADORES.PQR.KPI_COMPLIANCE_DESC'),
    color: 'text-n-slate-12',
  },
]);

const comoGrafica = filas => ({
  categories: filas.map(fila => fila.periodo),
  series: [
    {
      id: 'cantidad',
      label: t('HELIC3_INDICADORES.PQR.COUNT'),
      color: 'rgb(var(--blue-9))',
      data: filas.map(fila => fila.cantidad),
    },
  ],
});
const graficaMensual = computed(() => comoGrafica(datos.value?.mensual || []));

// Sin catalogo asociado (tipo/responsable), etiqueta es nil -- el frontend
// decide como traducirlo (mismo patron de GarantiasTab.vue, N3 de PR #113).
// "Sin asignar" reusa la clave ya existente de TICKETS.UNASSIGNED en vez de
// inventar una nueva para el mismo concepto.
const ETIQUETA_SIN_DATO = {
  BY_TYPE: 'NO_TYPE',
  BY_CATEGORY: 'NO_CATEGORY',
  BY_RESULT: 'NO_RESULT',
};
const etiquetaDe = (seccionTitulo, etiqueta) => {
  if (etiqueta !== null && etiqueta !== undefined) return etiqueta;
  if (seccionTitulo === 'BY_RESPONSIBLE') return t('TICKETS.UNASSIGNED');
  const clave = ETIQUETA_SIN_DATO[seccionTitulo];
  return clave ? t(`HELIC3_INDICADORES.PQR.${clave}`) : etiqueta;
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Filtros -->
    <div class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1">
      <div class="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
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
      <div class="flex justify-end mt-3">
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
                  {{ t('HELIC3_INDICADORES.PQR.MONTHLY') }}
                </p>
                <p class="mt-1 mb-3 text-xs text-n-slate-11">
                  {{ t('HELIC3_INDICADORES.PQR.MONTHLY_SUBTITLE') }}
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
                    {{ t('HELIC3_INDICADORES.PQR.COUNT') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.PQR.KPI_RESPONDED') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.PQR.KPI_PENDING') }}
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
                    {{ fila.respondidas }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-amber-11">
                    {{ fila.pendientes }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.PQR.MONTHLY_CHART') }}
            </p>
            <p class="mt-1 mb-2 text-xs text-n-slate-11">
              {{ t('HELIC3_INDICADORES.PQR.MONTHLY_SUBTITLE') }}
            </p>
            <BarChart
              v-if="datos.mensual.length"
              :data="graficaMensual"
              :height="ALTURA_GRAFICA"
              :aria-label="t('HELIC3_INDICADORES.PQR.MONTHLY_CHART')"
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
                {{ t('HELIC3_INDICADORES.PQR.QUARTERLY') }}
              </p>
              <p class="mt-1 mb-3 text-xs text-n-slate-11">
                {{ t('HELIC3_INDICADORES.PQR.QUARTERLY_SUBTITLE') }}
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
                  {{ t('HELIC3_INDICADORES.PQR.QUARTER_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.PQR.COUNT') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.PQR.KPI_RESPONDED') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.PQR.KPI_PENDING') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="fila in datos.trimestral"
                :key="fila.periodo"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 text-n-slate-11">{{ fila.periodo }}</td>
                <td
                  class="px-3 py-2 text-right font-medium tabular-nums text-n-slate-12"
                >
                  {{ fila.cantidad }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-teal-11">
                  {{ fila.respondidas }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-amber-11">
                  {{ fila.pendientes }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Motivo por trimestre -->
        <div
          class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-x-auto"
        >
          <div class="flex items-start justify-between">
            <div>
              <p class="font-semibold text-n-slate-12">
                {{ t('HELIC3_INDICADORES.PQR.MOTIVE_QUARTER') }}
              </p>
              <p class="mt-1 mb-3 text-xs text-n-slate-11">
                {{ t('HELIC3_INDICADORES.PQR.MOTIVE_QUARTER_SUBTITLE') }}
              </p>
            </div>
            <Button
              icon="i-lucide-download"
              variant="ghost"
              color="slate"
              size="xs"
              :is-loading="descargando.motivo_por_trimestre"
              :title="t('HELIC3_INDICADORES.DOWNLOAD')"
              @click="descargarCsv('motivo_por_trimestre')"
            />
          </div>
          <table class="w-full min-w-[32rem] text-sm">
            <thead class="text-xs text-n-slate-11">
              <tr>
                <th class="px-3 py-2 text-left font-medium">
                  {{ t('HELIC3_INDICADORES.PQR.MOTIVE_COLUMN') }}
                </th>
                <th
                  v-for="columna in COLUMNAS_TRIMESTRE"
                  :key="columna"
                  class="px-3 py-2 text-right font-medium"
                >
                  {{ columna }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.PQR.TOTAL_COLUMN') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="fila in datos.motivo_por_trimestre"
                :key="fila.motivo"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 text-n-slate-11">
                  {{ fila.motivo ?? t('HELIC3_INDICADORES.PQR.NO_MOTIVE') }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.t1 }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.t2 }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.t3 }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.t4 }}
                </td>
                <td
                  class="px-3 py-2 text-right font-medium tabular-nums text-n-slate-12"
                >
                  {{ fila.total }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Desgloses -->
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <table
            v-for="seccion in [
              { titulo: 'BY_TYPE', clave: 'por_tipo', filas: datos.por_tipo },
              {
                titulo: 'BY_CATEGORY',
                clave: 'por_categoria',
                filas: datos.por_categoria,
              },
              {
                titulo: 'BY_RESULT',
                clave: 'por_resultado',
                filas: datos.por_resultado,
              },
              {
                titulo: 'BY_RESPONSIBLE',
                clave: 'por_responsable',
                filas: datos.por_responsable,
              },
            ]"
            :key="seccion.titulo"
            class="w-full text-sm rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <caption class="p-3 caption-top">
              <div class="flex items-center justify-between">
                <span class="font-semibold text-left text-n-slate-12">
                  {{ t(`HELIC3_INDICADORES.PQR.${seccion.titulo}`) }}
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
