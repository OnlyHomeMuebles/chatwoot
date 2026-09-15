<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CreateTicketDialog from 'dashboard/components/widgets/conversation/CreateTicketDialog.vue';

// Bandeja de PQR (BAN-01 + VIS-02). Usa su store propio (pqrInbox), NO el del panel
// de conversacion. Los filtros, la paginacion y las metricas se resuelven en el
// servidor (GET helic3/pqr). El semaforo se deriva en cliente con los umbrales.
const store = useStore();
const route = useRoute();
const router = useRouter();
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
  sin_responder: false,
});
const pagina = ref(1);

// «Nueva PQR» abre el mismo dialogo del panel de conversacion, sin
// conversationId: Radicar funciona sin conversacion (VIS-02, revision de Jhan).
const dialogoNuevoRef = ref(null);
const abrirNuevaPqr = () => dialogoNuevoRef.value.open();

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
  store
    .dispatch('tickets/getCatalogos')
    .catch(() => useAlert(t('TICKETS.INBOX.CATALOGS_ERROR')));
  store.dispatch('agents/get');
  cargar();
});

const resetYCargar = () => {
  pagina.value = 1;
  cargar();
};

// Los selectores/pestañas recargan de inmediato; el buscador con debounce.
watch(
  () => [
    filtros.categoria_id,
    filtros.tipo_id,
    filtros.etapa_id,
    filtros.assignee_id,
    filtros.vencidas,
    filtros.sin_responder,
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

// Los filtros vigentes como query params: al abrir el expediente, "volver"
// los conserva.
const filtrosActivos = () => {
  const query = {};
  Object.entries(filtros).forEach(([clave, valor]) => {
    if (valor !== '' && valor !== false) query[clave] = valor;
  });
  return query;
};

// Clic en la fila navega al detalle (DET-01) por nombre de ruta, con los filtros.
const irAlDetalle = fila => {
  router.push({
    name: 'helic3_pqr_detail',
    params: { accountId: route.params.accountId, id: fila.id },
    query: filtrosActivos(),
  });
};

const emptyOption = label => ({ value: '', label });

// La categoria viene embebida en los motivos (API-01); se derivan las unicas.
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

// Tabbar por estado. "Sin responder" es un filtro propio; "En análisis" y
// "Respondidas" mapean a la etapa por su codigo del catalogo.
const TABS = [
  { key: 'all', label: t('TICKETS.INBOX.TABS.ALL') },
  { key: 'unanswered', label: t('TICKETS.INBOX.TABS.UNANSWERED') },
  { key: 'in_review', label: t('TICKETS.INBOX.TABS.IN_REVIEW') },
  { key: 'answered', label: t('TICKETS.INBOX.TABS.ANSWERED') },
];
const tabActivo = ref('all');
const etapaIdPorCodigo = codigo =>
  (catalogos.value.etapas_pqr || []).find(e => e.codigo === codigo)?.id || '';

const aplicarTab = key => {
  tabActivo.value = key;
  filtros.sin_responder = key === 'unanswered';
  if (key === 'in_review') filtros.etapa_id = etapaIdPorCodigo('en_analisis');
  else if (key === 'answered')
    filtros.etapa_id = etapaIdPorCodigo('respondida');
  else filtros.etapa_id = '';
};

// El color del semaforo se deriva: dias_habiles_restantes contra los umbrales del
// meta. No se duplica la regla de dias habiles; solo el mapeo trivial a color.
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
  ({ verde: 'bg-n-teal-9', amarillo: 'bg-n-amber-9', rojo: 'bg-n-ruby-9' })[
    semaforo
  ] || '';

const rangoTexto = computed(() =>
  t('TICKETS.INBOX.COUNT', {
    shown: records.value.length,
    total: meta.value.count,
  })
);

const estaVencido = fila =>
  !fila.reloj_detenido &&
  fila.plazo_respuesta_vence_at &&
  new Date(fila.plazo_respuesta_vence_at) < new Date();

// Cinco metricas (VIS-02): valor, unidad pequeña y linea de contexto. Los
// porcentajes se calculan sobre el total del filtro (meta.count).
const metricas = computed(() => meta.value.metricas);
// ruby queda reservado para vencido (el chip de la columna Plazo ya lo usa);
// "vencen esta semana" es una alerta previa, no un incumplimiento, por eso va
// en ambar (revision de Jhan en VIS-02).
const metricaValueClass = tone =>
  ({ good: 'text-n-teal-11', caution: 'text-n-amber-11' })[tone] ||
  'text-n-slate-12';

const metricasCards = computed(() => {
  const m = metricas.value;
  if (!m) return [];
  const total = meta.value.count || 0;
  const pct = n => (total ? Math.round((n / total) * 100) : 0);
  const ratio = n => t('TICKETS.INBOX.METRICS.RATIO', { n, total });
  return [
    {
      label: t('TICKETS.INBOX.METRICS.FILED'),
      value: m.radicadas,
      context: t('TICKETS.INBOX.METRICS.EXCL_INFO'),
    },
    {
      label: t('TICKETS.INBOX.METRICS.ON_TIME'),
      value: pct(m.dentro_plazo),
      unit: '%',
      tone: 'good',
      context: ratio(m.dentro_plazo),
    },
    {
      label: t('TICKETS.INBOX.METRICS.UNANSWERED'),
      value: m.sin_responder,
      context: '',
    },
    {
      label: t('TICKETS.INBOX.METRICS.WARRANTY'),
      value: pct(m.abren_garantia),
      unit: '%',
      context: ratio(m.abren_garantia),
    },
    {
      label: t('TICKETS.INBOX.METRICS.DUE_WEEK'),
      value: m.vencen_semana,
      tone: m.vencen_semana ? 'caution' : '',
      context: t('TICKETS.INBOX.METRICS.DUE_WEEK_CTX'),
    },
  ];
});

// Etapa como chip: Respondida verde, Cerrada neutro, el resto azul.
const etapaTagClass = codigo =>
  ({
    respondida: 'bg-n-teal-3 text-n-teal-11',
    cerrada: 'bg-n-slate-3 text-n-slate-11',
  })[codigo] || 'bg-n-blue-3 text-n-blue-11';

// Plazo como chip con punto de semaforo: respondida dentro del plazo, vencida,
// dias restantes, o una raya. Conserva la regla: sin umbrales, no se pinta color.
const relojPill = fila => {
  if (fila.respondida_at) {
    return {
      text: t('TICKETS.INBOX.CLOCK.ANSWERED'),
      cls: 'bg-n-teal-3 text-n-teal-11',
      dot: 'bg-n-teal-9',
    };
  }
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
  return null;
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <!-- Cabecera: titulo, subtitulo, acciones y tira de metricas -->
    <header
      class="flex flex-col gap-4 px-6 py-4 border-b border-n-weak shrink-0"
    >
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
        <span
          v-tooltip="t('TICKETS.INBOX.EXPORT_DISABLED')"
          class="inline-flex"
        >
          <Button
            :label="t('TICKETS.INBOX.EXPORT')"
            variant="outline"
            color="slate"
            size="sm"
            disabled
          />
        </span>
        <Button
          :label="t('TICKETS.INBOX.NEW')"
          icon="i-lucide-plus"
          color="blue"
          size="sm"
          @click="abrirNuevaPqr"
        />
      </div>

      <div
        v-if="metricasCards.length"
        class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5"
      >
        <div
          v-for="tarjeta in metricasCards"
          :key="tarjeta.label"
          class="flex flex-col gap-0.5 p-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">{{ tarjeta.label }}</span>
          <span
            class="flex items-baseline gap-0.5 text-2xl font-semibold leading-none tracking-tight tabular-nums"
            :class="metricaValueClass(tarjeta.tone)"
          >
            {{ tarjeta.value }}
            <span
              v-if="tarjeta.unit"
              class="text-sm font-medium text-n-slate-10"
            >
              {{ tarjeta.unit }}
            </span>
          </span>
          <span v-if="tarjeta.context" class="text-xs text-n-slate-10">
            {{ tarjeta.context }}
          </span>
        </div>
      </div>
    </header>

    <!-- Tarjeta contenedora con su cabecera (tabbar + filtros) y la tabla -->
    <div class="flex-1 p-6 overflow-hidden">
      <div
        class="flex flex-col h-full overflow-hidden rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
      >
        <div
          class="flex flex-wrap items-center gap-2 p-3 border-b border-n-weak shrink-0"
        >
          <div class="flex gap-1 p-0.5 rounded-lg bg-n-alpha-1">
            <button
              v-for="tab in TABS"
              :key="tab.key"
              class="px-3 py-1 text-sm font-medium rounded-md"
              :class="
                tabActivo === tab.key
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="aplicarTab(tab.key)"
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
        </div>

        <div class="flex-1 overflow-auto">
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
            <thead
              class="sticky top-0 z-10 text-left bg-n-solid-1 text-n-slate-11"
            >
              <tr class="border-b border-n-weak">
                <th class="px-6 py-3 font-medium">
                  {{ t('TICKETS.INBOX.COLUMNS.CLIENT') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('TICKETS.INBOX.COLUMNS.RADICADO') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('TICKETS.INBOX.COLUMNS.MOTIVE') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('TICKETS.INBOX.COLUMNS.STAGE') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('TICKETS.INBOX.COLUMNS.WARRANTY') }}
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
                class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1"
                role="button"
                tabindex="0"
                @click="irAlDetalle(fila)"
                @keydown.enter="irAlDetalle(fila)"
                @keydown.space.prevent="irAlDetalle(fila)"
              >
                <td class="px-6 py-3">
                  <p class="mb-0 font-medium text-n-slate-12">
                    {{ fila.cliente?.nombre || fila.title }}
                  </p>
                  <p class="mb-0 tabular-nums text-n-slate-11">
                    {{ fila.cliente?.documento || t('TICKETS.INBOX.PENDING') }}
                  </p>
                </td>
                <td class="px-4 py-3">
                  <p class="mb-0 font-medium tabular-nums text-n-slate-12">
                    {{ fila.numero_radicado || t('TICKETS.INBOX.NO_RADICADO') }}
                  </p>
                  <p class="mb-0 text-xs text-n-slate-10">
                    {{
                      [fila.categoria?.nombre, fila.tipo?.nombre]
                        .filter(Boolean)
                        .join(' · ')
                    }}
                  </p>
                </td>
                <td class="px-4 py-3">
                  <p class="mb-0 text-n-slate-12">
                    {{ fila.motivo_pqr?.nombre || t('TICKETS.INBOX.PENDING') }}
                  </p>
                  <p v-if="fila.ciudad" class="mb-0 text-xs text-n-slate-10">
                    {{ fila.ciudad }}
                  </p>
                </td>
                <td class="px-4 py-3">
                  <div class="flex flex-wrap items-center gap-1">
                    <span
                      v-if="fila.etapa"
                      class="px-2 py-0.5 text-xs font-medium rounded-md"
                      :class="etapaTagClass(fila.etapa.codigo)"
                    >
                      {{ fila.etapa.nombre }}
                    </span>
                    <span v-else class="text-n-slate-10">—</span>
                    <span
                      v-if="fila.escalamiento"
                      class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-amber-3 text-n-amber-11"
                    >
                      {{ fila.escalamiento }}
                    </span>
                  </div>
                </td>
                <td class="px-4 py-3">
                  <template v-if="fila.garantia">
                    <p class="mb-0 tabular-nums text-n-slate-12">
                      {{ fila.garantia.numero_radicado }}
                    </p>
                    <p
                      v-if="fila.garantia.proceso"
                      class="mb-0 text-xs text-n-slate-10"
                    >
                      {{ fila.garantia.proceso }}
                    </p>
                  </template>
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
                      <Icon
                        icon="i-lucide-user"
                        class="size-3.5 text-n-slate-10"
                      />
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
          class="flex items-center justify-between gap-3 p-3 border-t border-n-weak shrink-0"
        >
          <span class="text-xs text-n-slate-10">{{ rangoTexto }}</span>
          <div class="flex items-center gap-3">
            <Button
              :label="t('TICKETS.INBOX.PAGINATION.PREV')"
              icon="i-lucide-chevron-left"
              variant="faded"
              color="slate"
              size="xs"
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
              variant="faded"
              color="slate"
              size="xs"
              :disabled="pagina >= totalPaginas"
              @click="irAPagina(pagina + 1)"
            />
          </div>
        </div>
      </div>
    </div>

    <CreateTicketDialog ref="dialogoNuevoRef" @created="cargar" />
  </div>
</template>
