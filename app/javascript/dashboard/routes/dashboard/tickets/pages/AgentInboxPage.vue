<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Bandeja del Agente IA (AGT-04): supervision de lo que el bot HELIC3 radico
// solo -- NO es una bandeja de edicion (por eso no hay filtros de categoria/tipo
// ni un boton "Nueva PQR", que si tiene la bandeja humana en TICKETS.INBOX). Usa
// el MISMO store pqrInbox que esa bandeja, con origen: 'agente' fijo: el backend
// ya sabe filtrar por eso (pqr_controller.rb#filtrar_por_origen), asi que no hace
// falta un store ni un endpoint propios.
//
// El bot no es un AgentBot nativo asignado a la conversacion (funciona por
// webhook, ver WEBHOOK.md); la unica senal de "esto lo atendio el agente" es
// que el ticket haya nacido con origen: agente (radicar_pqr_tool). Por eso esta
// bandeja solo muestra casos que YA se radicaron -- una conversacion donde el
// bot solo respondio una duda de FAQ, sin PQR, no aparece aqui.
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const records = useMapGetter('pqrInbox/getRecords');
const meta = useMapGetter('pqrInbox/getMeta');
const uiFlags = useMapGetter('pqrInbox/getUIFlags');

const pagina = ref(1);

const cargar = async () => {
  try {
    await store.dispatch('pqrInbox/fetch', {
      origen: 'agente',
      page: pagina.value,
    });
  } catch (error) {
    useAlert(t('TICKETS.AGENT_INBOX.ERROR'));
  }
};

onMounted(cargar);

const irAPagina = destino => {
  pagina.value = destino;
  cargar();
};

const totalPaginas = computed(() =>
  Math.max(1, Math.ceil((meta.value.count || 0) / (meta.value.perPage || 25)))
);

const rangoTexto = computed(() =>
  t('TICKETS.INBOX.COUNT', {
    shown: records.value.length,
    total: meta.value.count,
  })
);

// Tres metricas del mismo bloque que ya calcula el backend (VIS-02), aqui
// acotadas por el filtro origen=agente porque @metricas se arma sobre
// aplicar_filtros(...) -- no hay que duplicar ninguna cuenta.
const metricasCards = computed(() => {
  const m = meta.value.metricas;
  if (!m) return [];
  return [
    { label: t('TICKETS.AGENT_INBOX.METRICS.RADICADAS'), value: m.radicadas },
    {
      label: t('TICKETS.AGENT_INBOX.METRICS.ABREN_GARANTIA'),
      value: m.abren_garantia,
    },
    {
      label: t('TICKETS.AGENT_INBOX.METRICS.SIN_RESPONDER'),
      value: m.sin_responder,
    },
  ];
});

const clasificacionTexto = fila =>
  [fila.tipo?.nombre, fila.motivo_pqr?.nombre, fila.categoria?.nombre]
    .filter(Boolean)
    .join(' · ');

const etapaTagClass = codigo =>
  ({
    respondida: 'bg-n-teal-3 text-n-teal-11',
    cerrada: 'bg-n-slate-3 text-n-slate-11',
  })[codigo] || 'bg-n-blue-3 text-n-blue-11';

// Clic en la fila abre la conversacion REAL de Chatwoot (no una pantalla propia
// de HELIC3): esta bandeja es de supervision, el detalle vive en el hilo real.
// conversation_display_id es el id publico de Chatwoot, no el id de BD (mismo
// patron que PqrDetailPage.vue#conversacionUrl).
const irALaConversacion = fila => {
  if (!fila.conversation_display_id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: fila.conversation_display_id,
    },
  });
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex flex-col gap-4 px-6 py-4 border-b border-n-weak shrink-0"
    >
      <div class="flex flex-wrap items-end gap-3">
        <div class="flex flex-col gap-1 min-w-0">
          <h1 class="mb-0 text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('TICKETS.AGENT_INBOX.TITLE') }}
          </h1>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('TICKETS.AGENT_INBOX.SUBTITLE') }}
          </p>
        </div>
        <div class="flex-1" />
        <span class="text-sm text-n-slate-11">{{ rangoTexto }}</span>
      </div>

      <div
        v-if="metricasCards.length"
        class="grid grid-cols-3 gap-3 sm:max-w-md"
      >
        <div
          v-for="tarjeta in metricasCards"
          :key="tarjeta.label"
          class="flex flex-col gap-0.5 p-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">{{ tarjeta.label }}</span>
          <span
            class="text-2xl font-semibold leading-none tracking-tight tabular-nums text-n-slate-12"
          >
            {{ tarjeta.value }}
          </span>
        </div>
      </div>
    </header>

    <div class="flex-1 p-6 overflow-hidden">
      <div
        class="flex flex-col h-full overflow-hidden rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
      >
        <div class="flex-1 overflow-auto">
          <div
            v-if="uiFlags.isFetching"
            class="flex items-center justify-center py-12 text-n-slate-11"
          >
            <Spinner :size="24" />
          </div>
          <div
            v-else-if="!records.length"
            class="flex flex-col items-center justify-center gap-1 py-12 text-center text-n-slate-11"
          >
            <p class="mb-0">{{ t('TICKETS.AGENT_INBOX.EMPTY') }}</p>
            <p class="mb-0 text-xs text-n-slate-10">
              {{ t('TICKETS.AGENT_INBOX.EMPTY_HINT') }}
            </p>
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
                  {{ t('TICKETS.AGENT_INBOX.COLUMNS.CLASSIFICATION') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('TICKETS.INBOX.COLUMNS.WARRANTY') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('TICKETS.INBOX.COLUMNS.STAGE') }}
                </th>
                <th class="px-4 py-3 font-medium" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="fila in records"
                :key="fila.id"
                class="border-b border-n-weak"
                :class="
                  fila.conversation_display_id
                    ? 'cursor-pointer hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1'
                    : 'opacity-60'
                "
                role="button"
                tabindex="0"
                @click="irALaConversacion(fila)"
                @keydown.enter="irALaConversacion(fila)"
                @keydown.space.prevent="irALaConversacion(fila)"
              >
                <td class="px-6 py-3">
                  <p class="mb-0 font-medium text-n-slate-12">
                    {{ fila.cliente?.nombre || fila.title }}
                  </p>
                  <p class="mb-0 tabular-nums text-n-slate-11">
                    {{ fila.cliente?.documento || t('TICKETS.INBOX.PENDING') }}
                  </p>
                </td>
                <td class="px-4 py-3 font-medium tabular-nums text-n-slate-12">
                  {{ fila.numero_radicado || t('TICKETS.INBOX.NO_RADICADO') }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ clasificacionTexto(fila) || t('TICKETS.INBOX.PENDING') }}
                </td>
                <td class="px-4 py-3">
                  <span
                    v-if="fila.garantia"
                    class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-iris-3 text-n-iris-11"
                  >
                    {{ fila.garantia.numero_radicado }}
                  </span>
                  <span v-else class="text-n-slate-10">—</span>
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
                <td class="px-4 py-3 text-right">
                  <span
                    v-if="fila.conversation_display_id"
                    v-tooltip="t('TICKETS.AGENT_INBOX.OPEN_CONVERSATION')"
                    class="inline-flex"
                  >
                    <Icon
                      icon="i-lucide-messages-square"
                      class="size-4 text-n-slate-10"
                    />
                  </span>
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
  </div>
</template>
