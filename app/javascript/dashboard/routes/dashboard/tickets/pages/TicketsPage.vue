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

const etapaOptions = computed(() => [
  emptyOption(t('TICKETS.INBOX.FILTERS.ALL_STAGES')),
  ...(catalogos.value.etapas_pqr || []).map(x => ({
    value: x.id,
    label: x.nombre,
  })),
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
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('TICKETS.INBOX.TITLE') }}
      </h1>
      <span class="text-sm text-n-slate-11">{{ rangoTexto }}</span>
    </header>

    <div
      class="flex flex-wrap items-center gap-2 px-6 py-3 border-b border-n-weak"
    >
      <Input
        v-model="filtros.q"
        :placeholder="t('TICKETS.INBOX.FILTERS.SEARCH')"
        class="w-56"
      />
      <Select v-model="filtros.categoria_id" :options="categoriaOptions" />
      <Select v-model="filtros.tipo_id" :options="tipoOptions" />
      <Select v-model="filtros.etapa_id" :options="etapaOptions" />
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
            <td class="px-4 py-3 text-n-slate-11">
              {{ fila.etapa?.nombre || '—' }}
            </td>
            <td class="px-4 py-3">
              <div
                class="flex items-center gap-1.5"
                :class="fila.reloj_detenido ? 'opacity-60' : ''"
              >
                <span
                  v-if="semaforoDeFila(fila)"
                  class="rounded-full size-2 shrink-0"
                  :class="semaforoDotClass(semaforoDeFila(fila))"
                />
                <span v-if="fila.reloj_detenido" class="text-n-slate-11">
                  {{ t('TICKETS.INBOX.CLOCK.FROZEN') }}
                </span>
                <span
                  v-else-if="estaVencido(fila)"
                  class="font-medium text-n-ruby-11"
                >
                  {{ t('TICKETS.INBOX.CLOCK.OVERDUE') }}
                </span>
                <span
                  v-else-if="fila.plazo_respuesta_vence_at"
                  class="text-n-slate-11"
                >
                  {{
                    t('TICKETS.INBOX.CLOCK.DUE', {
                      date: formatFecha(fila.plazo_respuesta_vence_at),
                    })
                  }}
                </span>
                <span v-else class="text-n-slate-10">—</span>
              </div>
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
      <span class="text-sm text-n-slate-11"
        >{{ pagina }} / {{ totalPaginas }}</span
      >
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
