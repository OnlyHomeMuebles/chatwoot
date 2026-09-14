<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Bandeja de PQR (BAN-01). Usa su store propio (pqrInbox), NO el del panel de
// conversacion: abrir la bandeja no altera lo que el panel ya tenia cargado.
// Los filtros y la paginacion se resuelven en el servidor (GET helic3/pqr).
const store = useStore();
const { t } = useI18n();

const records = useMapGetter('pqrInbox/getRecords');
const meta = useMapGetter('pqrInbox/getMeta');
const uiFlags = useMapGetter('pqrInbox/getUIFlags');
const catalogos = useMapGetter('tickets/getCatalogos');
const agents = useMapGetter('agents/getAgents');

const filtros = reactive({
  categoria_id: '',
  tipo_id: '',
  etapa_id: '',
  assignee_id: '',
  q: '',
  vencidas: false,
});
const pagina = ref(1);

const cargar = async () => {
  const params = { page: pagina.value };
  Object.entries(filtros).forEach(([clave, valor]) => {
    if (valor !== '' && valor !== false) params[clave] = valor;
  });
  try {
    await store.dispatch('pqrInbox/fetch', params);
  } catch (error) {
    useAlert(t('TICKETS.INBOX.ERROR'));
  }
};

onMounted(() => {
  // getCatalogos propaga el error a proposito; sin catch quedaria una promesa
  // rechazada y los filtros vacios sin aviso.
  store
    .dispatch('tickets/getCatalogos')
    .catch(() => useAlert(t('TICKETS.INBOX.CATALOGS_ERROR')));
  store.dispatch('agents/get');
  cargar();
});

// Una sola via de recarga: al cambiar un filtro se vuelve a la pagina 1 y se
// carga; los botones de paginacion llaman cargar() directo. pagina NO tiene watch,
// para no disparar dos peticiones (era la familia del bug de PAN-01).
const resetYCargar = () => {
  pagina.value = 1;
  cargar();
};

// Los selectores recargan de inmediato; el buscador de texto con debounce de
// 300 ms para no disparar una peticion por tecla.
watch(
  () => [
    filtros.categoria_id,
    filtros.tipo_id,
    filtros.etapa_id,
    filtros.assignee_id,
    filtros.vencidas,
  ],
  resetYCargar
);

let debounceBusqueda = null;
watch(
  () => filtros.q,
  () => {
    clearTimeout(debounceBusqueda);
    debounceBusqueda = setTimeout(resetYCargar, 300);
  }
);

const irAPagina = destino => {
  pagina.value = destino;
  cargar();
};

const emptyOption = label => ({ value: '', label });

// La categoria no viene como catalogo propio (API-01 la trae embebida en los
// motivos); se derivan las unicas de ahi para el filtro.
const categoriaOptions = computed(() => {
  const vistas = new Map();
  (catalogos.value.motivos_pqr || []).forEach(motivo => {
    if (motivo.categoria) vistas.set(motivo.categoria.id, motivo.categoria);
  });
  return [
    emptyOption(t('TICKETS.INBOX.FILTERS.ALL_CATEGORIES')),
    ...[...vistas.values()].map(c => ({ value: c.id, label: c.nombre })),
  ];
});

const tipoOptions = computed(() => [
  emptyOption(t('TICKETS.INBOX.FILTERS.ALL_TYPES')),
  ...(catalogos.value.tipos || []).map(x => ({ value: x.id, label: x.nombre })),
]);

const assigneeOptions = computed(() => [
  emptyOption(t('TICKETS.INBOX.FILTERS.ALL_ASSIGNEES')),
  ...agents.value.map(a => ({ value: a.id, label: a.name })),
]);

const totalPaginas = computed(() =>
  Math.max(1, Math.ceil((meta.value.count || 0) / (meta.value.perPage || 25)))
);

// El color del semaforo se deriva en el cliente: dias_habiles_restantes (que
// calcula el servidor) contra los umbrales del catalogo que vienen en el meta.
// No se duplica la regla de dias habiles; solo el mapeo trivial a color.
const semaforoDeFila = fila => {
  const dias = fila.dias_habiles_restantes;
  const { umbralVerde, umbralAmarillo } = meta.value;
  if (
    typeof dias !== 'number' ||
    umbralVerde == null ||
    umbralAmarillo == null
  ) {
    return null;
  }
  if (dias >= umbralVerde) return 'verde';
  if (dias >= umbralAmarillo) return 'amarillo';
  return 'rojo';
};

const semaforoDotClass = semaforo =>
  ({
    verde: 'bg-n-teal-9',
    amarillo: 'bg-n-amber-9',
    rojo: 'bg-n-ruby-9',
  })[semaforo] || '';

const rangoTexto = computed(() => {
  const mostrados = records.value.length;
  return t('TICKETS.INBOX.COUNT', {
    shown: mostrados,
    total: meta.value.count,
  });
});

const clasificacionTexto = fila =>
  [fila.tipo?.nombre, fila.motivo_pqr?.nombre, fila.categoria?.nombre]
    .filter(Boolean)
    .join(' · ');

const estaVencido = fila =>
  !fila.reloj_detenido &&
  fila.plazo_respuesta_vence_at &&
  new Date(fila.plazo_respuesta_vence_at) < new Date();

const formatFecha = valor =>
  valor ? new Date(valor).toLocaleDateString() : null;

const statusDotClass = status =>
  ({
    open: 'bg-n-teal-9',
    pending: 'bg-n-amber-9',
    resolved: 'bg-n-blue-9',
    closed: 'bg-n-slate-9',
  })[status] || 'bg-n-slate-9';

// Tira de metricas (KPIs de la cuenta) que llega en el meta. "Dentro de plazo"
// es el complemento de las vencidas; no recalcula dias habiles en el cliente.
const metricas = computed(() => meta.value.metricas);
const metricasCards = computed(() => {
  const m = metricas.value;
  if (!m) return [];
  const pct = m.total
    ? Math.round(((m.total - m.vencidas) / m.total) * 100)
    : 0;
  return [
    { label: t('TICKETS.INBOX.METRICS.FILED'), value: m.total },
    {
      label: t('TICKETS.INBOX.METRICS.ON_TIME'),
      value: `${pct}%`,
      tone: 'good',
    },
    { label: t('TICKETS.INBOX.METRICS.UNANSWERED'), value: m.sin_responder },
    {
      label: t('TICKETS.INBOX.METRICS.OVERDUE'),
      value: m.vencidas,
      tone: m.vencidas ? 'warn' : '',
    },
  ];
});
const metricaValueClass = tone =>
  ({ good: 'text-n-teal-11', warn: 'text-n-ruby-11' })[tone] ||
  'text-n-slate-12';

// Pestañas de etapa: reemplazan el selector de etapa por accesos rápidos.
const etapaTabs = computed(() => [
  { value: '', label: t('TICKETS.INBOX.FILTERS.ALL_STAGES') },
  ...(catalogos.value.etapas_pqr || []).map(x => ({
    value: x.id,
    label: x.nombre,
  })),
]);

// Etapa como pastilla de color por codigo del catalogo.
const etapaTagClass = codigo =>
  ({
    nueva: 'bg-n-blue-3 text-n-blue-11',
    en_analisis: 'bg-n-amber-3 text-n-amber-11',
    respondida: 'bg-n-teal-3 text-n-teal-11',
    cerrada: 'bg-n-slate-3 text-n-slate-11',
  })[codigo] || 'bg-n-slate-3 text-n-slate-11';

// Plazo como pastilla de semaforo con los dias habiles restantes.
const relojPill = fila => {
  if (fila.reloj_detenido) {
    return {
      text: t('TICKETS.INBOX.CLOCK.FROZEN'),
      cls: 'bg-n-slate-3 text-n-slate-11',
      dot: 'bg-n-slate-9',
    };
  }
  if (estaVencido(fila)) {
    const dias =
      typeof fila.dias_habiles_restantes === 'number'
        ? Math.abs(fila.dias_habiles_restantes)
        : null;
    return {
      text:
        dias != null
          ? t('TICKETS.CLOCK.OVERDUE', { days: dias })
          : t('TICKETS.INBOX.CLOCK.OVERDUE'),
      cls: 'bg-n-ruby-3 text-n-ruby-11',
      dot: 'bg-n-ruby-9',
    };
  }
  if (typeof fila.dias_habiles_restantes === 'number') {
    const sem = semaforoDeFila(fila);
    const cls =
      {
        verde: 'bg-n-teal-3 text-n-teal-11',
        amarillo: 'bg-n-amber-3 text-n-amber-11',
        rojo: 'bg-n-ruby-3 text-n-ruby-11',
      }[sem] || 'bg-n-slate-3 text-n-slate-11';
    return {
      text: t('TICKETS.CLOCK.REMAINING', { days: fila.dias_habiles_restantes }),
      cls,
      dot: semaforoDotClass(sem) || 'bg-n-slate-9',
    };
  }
  if (fila.plazo_respuesta_vence_at) {
    return {
      text: t('TICKETS.INBOX.CLOCK.DUE', {
        date: formatFecha(fila.plazo_respuesta_vence_at),
      }),
      cls: 'bg-n-slate-3 text-n-slate-11',
      dot: 'bg-n-slate-9',
    };
  }
  return null;
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header class="flex flex-col gap-4 px-6 py-4 border-b border-n-weak">
      <div class="flex flex-wrap items-end gap-3">
        <div class="flex flex-col gap-1 min-w-0">
          <h1 class="mb-0 text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('TICKETS.INBOX.TITLE') }}
          </h1>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('TICKETS.INBOX.SUBTITLE') }}
          </p>
        </div>
        <div class="flex-1" />
        <span class="text-sm text-n-slate-11">{{ rangoTexto }}</span>
      </div>

      <!-- Tira de metricas (KPIs de la cuenta) -->
      <div
        v-if="metricasCards.length"
        class="grid grid-cols-2 gap-3 sm:grid-cols-4"
      >
        <div
          v-for="tarjeta in metricasCards"
          :key="tarjeta.label"
          class="flex flex-col gap-0.5 p-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">{{ tarjeta.label }}</span>
          <span
            class="text-2xl font-semibold tabular-nums tracking-tight"
            :class="metricaValueClass(tarjeta.tone)"
          >
            {{ tarjeta.value }}
          </span>
        </div>
      </div>
    </header>

    <!-- Pestañas por etapa + filtros -->
    <div
      class="flex flex-wrap items-center gap-2 px-6 py-3 border-b border-n-weak"
    >
      <div class="flex gap-1 p-0.5 rounded-lg bg-n-alpha-1">
        <button
          v-for="tab in etapaTabs"
          :key="tab.value"
          class="px-3 py-1 text-sm font-medium rounded-md"
          :class="
            filtros.etapa_id === tab.value
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="filtros.etapa_id = tab.value"
        >
          {{ tab.label }}
        </button>
      </div>
      <div class="flex-1" />
      <Input
        v-model="filtros.q"
        :placeholder="t('TICKETS.INBOX.FILTERS.SEARCH')"
        class="w-56"
      />
      <Select v-model="filtros.categoria_id" :options="categoriaOptions" />
      <Select v-model="filtros.tipo_id" :options="tipoOptions" />
      <Select v-model="filtros.assignee_id" :options="assigneeOptions" />
      <label
        class="flex items-center gap-2 text-sm cursor-pointer text-n-slate-11"
      >
        <input
          v-model="filtros.vencidas"
          type="checkbox"
          class="cursor-pointer"
        />
        {{ t('TICKETS.INBOX.FILTERS.OVERDUE') }}
      </label>
    </div>

    <div class="flex-1 overflow-y-auto">
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        <Spinner :size="24" />
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        {{ t('TICKETS.INBOX.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-6 py-3 font-medium">
              {{ t('TICKETS.INBOX.COLUMNS.CLIENT') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.INBOX.COLUMNS.RADICADO') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.INBOX.COLUMNS.CLASSIFICATION') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.INBOX.COLUMNS.STAGE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.INBOX.COLUMNS.CLOCK') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.INBOX.COLUMNS.ASSIGNEE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="fila in records"
            :key="fila.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-6 py-3">
              <p class="mb-0 font-medium text-n-slate-12">
                {{ fila.cliente?.nombre || fila.title }}
              </p>
              <p class="mb-0 text-n-slate-11">
                {{ fila.cliente?.documento || t('TICKETS.INBOX.PENDING') }}
              </p>
            </td>
            <td class="px-4 py-3 font-medium text-n-slate-12">
              <div class="flex items-center gap-1.5">
                <span
                  class="rounded-full size-2 shrink-0"
                  :class="statusDotClass(fila.status)"
                />
                {{ fila.numero_radicado || t('TICKETS.INBOX.NO_RADICADO') }}
              </div>
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ clasificacionTexto(fila) || t('TICKETS.INBOX.PENDING') }}
            </td>
            <td class="px-4 py-3">
              <span
                v-if="fila.etapa"
                class="px-2 py-0.5 text-xs font-medium rounded-md"
                :class="etapaTagClass(fila.etapa.codigo)"
              >
                {{ fila.etapa.nombre }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-4 py-3">
              <span
                v-if="relojPill(fila)"
                class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium rounded-md"
                :class="relojPill(fila).cls"
              >
                <span
                  class="rounded-full size-1.5"
                  :class="relojPill(fila).dot"
                />
                {{ relojPill(fila).text }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-4 py-3">
              <div class="flex items-center gap-2">
                <Avatar
                  v-if="fila.assignee"
                  :name="fila.assignee.name"
                  :src="fila.assignee.thumbnail"
                  :size="24"
                  rounded-full
                />
                <span
                  v-else
                  class="flex items-center justify-center rounded-full size-6 shrink-0 bg-n-alpha-2"
                >
                  <Icon icon="i-lucide-user" class="size-3.5 text-n-slate-10" />
                </span>
                <span class="text-n-slate-11">
                  {{ fila.assignee?.name || t('TICKETS.UNASSIGNED') }}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div
      v-if="records.length"
      class="flex items-center justify-end gap-3 px-6 py-3 border-t border-n-weak"
    >
      <Button
        :label="t('TICKETS.INBOX.PAGINATION.PREV')"
        icon="i-lucide-chevron-left"
        faded
        xs
        :disabled="pagina <= 1"
        @click="irAPagina(pagina - 1)"
      />
      <span class="text-sm tabular-nums text-n-slate-11">
        {{
          t('TICKETS.INBOX.PAGINATION.PAGE', {
            page: pagina,
            total: totalPaginas,
          })
        }}
      </span>
      <Button
        :label="t('TICKETS.INBOX.PAGINATION.NEXT')"
        icon="i-lucide-chevron-right"
        faded
        xs
        :disabled="pagina >= totalPaginas"
        @click="irAPagina(pagina + 1)"
      />
    </div>
  </div>
</template>
