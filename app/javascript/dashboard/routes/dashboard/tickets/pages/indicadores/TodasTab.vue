<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import { useIndicadoresStore } from 'dashboard/store/helic3/indicadores';

// "Todas las PQR" (mockup v12): un resumen de Garantías + Derechos de
// Petición juntos, sin mezclar sus tablas -- cada expediente sigue siendo
// su propio modelo con su propio reloj. Solo año/mes como filtro: son los
// únicos con el mismo significado en los dos expedientes (ver
// Helic3::Indicadores::Todas).
const { t, locale } = useI18n();
const indicadoresStore = useIndicadoresStore();

const datos = computed(() => indicadoresStore.getTodas);
const cargando = computed(() => indicadoresStore.getUIFlags.isFetchingTodas);

const ANIO_ACTUAL = new Date().getFullYear();
const ANIOS = Array.from({ length: 5 }, (_, i) => ANIO_ACTUAL - i);
const MESES = Array.from({ length: 12 }, (_, i) => i + 1);
const ALTURA_GRAFICA = 240;

const filtros = reactive({ anio: '', mes: '' });

const todos = () => ({ value: '', label: t('HELIC3_INDICADORES.FILTERS.ALL') });
const anioOptions = computed(() => [
  todos(),
  ...ANIOS.map(anio => ({ value: anio, label: String(anio) })),
]);

// N4 (mismo ajuste que GarantiasTab.vue/PqrTab.vue): nombres de mes, no 1-12.
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

const huboError = ref(false);

const cargar = async () => {
  const params = {};
  Object.entries(filtros).forEach(([clave, valor]) => {
    if (valor !== '') params[clave] = valor;
  });
  huboError.value = false;
  try {
    await indicadoresStore.fetchTodas(params);
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

onMounted(cargar);

watch(() => [filtros.anio, filtros.mes], cargar);

const sinDatos = computed(
  () => !!datos.value && datos.value.kpis.total_casos === 0
);

const kpiCards = computed(() => [
  {
    label: t('HELIC3_INDICADORES.TODAS.KPI_TOTAL'),
    valor: datos.value?.kpis.total_casos,
    descripcion: t('HELIC3_INDICADORES.TODAS.KPI_TOTAL_DESC'),
    color: 'text-n-slate-12',
  },
  {
    label: t('HELIC3_INDICADORES.TABS.GARANTIAS'),
    valor: datos.value?.kpis.garantias,
    descripcion: t('HELIC3_INDICADORES.TODAS.KPI_GARANTIAS_DESC'),
    color: 'text-n-slate-12',
  },
  {
    label: t('HELIC3_INDICADORES.TABS.PQR'),
    valor: datos.value?.kpis.pqr,
    descripcion: t('HELIC3_INDICADORES.TODAS.KPI_PQR_DESC'),
    color: 'text-n-slate-12',
  },
  {
    label: t('HELIC3_INDICADORES.TODAS.KPI_SOLVED'),
    valor: datos.value?.kpis.solucionadas,
    descripcion: t('HELIC3_INDICADORES.TODAS.KPI_SOLVED_DESC'),
    color: 'text-n-teal-11',
  },
  {
    label: t('HELIC3_INDICADORES.TODAS.KPI_IN_PROGRESS'),
    valor: datos.value?.kpis.en_proceso,
    descripcion: t('HELIC3_INDICADORES.TODAS.KPI_IN_PROGRESS_DESC'),
    color: 'text-n-amber-11',
  },
]);

const comoGrafica = filas => ({
  categories: filas.map(fila => fila.periodo),
  series: [
    {
      id: 'garantias',
      label: t('HELIC3_INDICADORES.TABS.GARANTIAS'),
      color: 'rgb(var(--blue-9))',
      data: filas.map(fila => fila.garantias),
    },
    {
      id: 'pqr',
      label: t('HELIC3_INDICADORES.TABS.PQR'),
      color: 'rgb(var(--amber-9))',
      data: filas.map(fila => fila.pqr),
    },
  ],
});
const graficaMensual = computed(() => comoGrafica(datos.value?.mensual || []));
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Filtros: solo año/mes, lo unico compartido entre Garantias y PQR -->
    <div class="flex flex-wrap items-end gap-3">
      <div class="min-w-0 space-y-1.5">
        <label class="block text-xs font-medium text-n-slate-11">
          {{ t('HELIC3_INDICADORES.FILTERS.YEAR') }}
        </label>
        <Select
          v-model="filtros.anio"
          :options="anioOptions"
          :aria-label="t('HELIC3_INDICADORES.FILTERS.YEAR')"
        />
      </div>
      <div class="min-w-0 space-y-1.5">
        <label class="block text-xs font-medium text-n-slate-11">
          {{ t('HELIC3_INDICADORES.FILTERS.MONTH') }}
        </label>
        <Select
          v-model="filtros.mes"
          :options="mesOptions"
          :aria-label="t('HELIC3_INDICADORES.FILTERS.MONTH')"
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

    <p class="text-xs text-n-slate-11">
      {{ t('HELIC3_INDICADORES.TODAS.SUBTITLE') }}
    </p>

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
          class="grid grid-cols-2 divide-x divide-y divide-n-weak rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 md:grid-cols-5 md:divide-y-0 overflow-hidden"
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

        <!-- Detalle mensual: tabla + grafica, garantias y pqr lado a lado -->
        <div class="grid grid-cols-1 gap-3 xl:grid-cols-[1.7fr_1fr]">
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-x-auto"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.TODAS.MONTHLY') }}
            </p>
            <table class="w-full min-w-[26rem] text-sm mt-3">
              <thead class="text-xs text-n-slate-11">
                <tr>
                  <th class="px-3 py-2 text-left font-medium">
                    {{ t('HELIC3_INDICADORES.FILTERS.MONTH') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.TABS.GARANTIAS') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.TABS.PQR') }}
                  </th>
                  <th class="px-3 py-2 text-right font-medium">
                    {{ t('HELIC3_INDICADORES.TODAS.TOTAL_COLUMN') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="fila in datos.mensual"
                  :key="fila.periodo"
                  class="border-t border-n-weak"
                >
                  <td class="px-3 py-2 text-n-slate-11">{{ fila.periodo }}</td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ fila.garantias }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ fila.pqr }}
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
          <div
            class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
          >
            <p class="font-semibold text-n-slate-12">
              {{ t('HELIC3_INDICADORES.TODAS.MONTHLY_CHART') }}
            </p>
            <BarChart
              v-if="datos.mensual.length"
              :data="graficaMensual"
              :height="ALTURA_GRAFICA"
              :aria-label="t('HELIC3_INDICADORES.TODAS.MONTHLY_CHART')"
            />
          </div>
        </div>

        <!-- Detalle trimestral -->
        <div
          class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-x-auto"
        >
          <p class="font-semibold text-n-slate-12">
            {{ t('HELIC3_INDICADORES.TODAS.QUARTERLY') }}
          </p>
          <table class="w-full min-w-[26rem] text-sm mt-3">
            <thead class="text-xs text-n-slate-11">
              <tr>
                <th class="px-3 py-2 text-left font-medium">
                  {{ t('HELIC3_INDICADORES.GARANTIAS.QUARTER_COLUMN') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.TABS.GARANTIAS') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.TABS.PQR') }}
                </th>
                <th class="px-3 py-2 text-right font-medium">
                  {{ t('HELIC3_INDICADORES.TODAS.TOTAL_COLUMN') }}
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
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.garantias }}
                </td>
                <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                  {{ fila.pqr }}
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
      </template>
    </template>
  </div>
</template>
