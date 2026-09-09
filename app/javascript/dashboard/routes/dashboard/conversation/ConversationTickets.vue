<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CreateTicketDialog from 'dashboard/components/widgets/conversation/CreateTicketDialog.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const STATUSES = ['open', 'pending', 'resolved', 'closed'];

const createDialogRef = ref(null);

const tickets = useMapGetter('tickets/getTickets');

// props.conversationId es el display_id (lo que Chatwoot expone como id de la
// conversacion en el dashboard). Se compara contra conversation_display_id, no
// contra conversation_id (que es el id de base de datos): así el panel muestra
// también los expedientes que radicó el agente, sin manipular ids del dominio.
const conversationTickets = computed(() =>
  tickets.value.filter(
    ticket => ticket.conversation_display_id === Number(props.conversationId)
  )
);

// el listado omite semaforo/dias (los deriva y encarecerian cada fila); se pide
// el detalle de los pocos tickets de esta conversacion para pintar el semaforo
const fetchDetails = () => {
  conversationTickets.value.forEach(ticket =>
    store.dispatch('tickets/show', ticket.id)
  );
};

// Refresca la LISTA y luego pide el detalle. Volver a pedir la lista es lo que
// hace aparecer un expediente que el agente radico en otra conversacion mientras
// el panel ya estaba abierto: tickets/get corre una sola vez al montar, así que
// sin este refresco ese expediente nunca entraria al store.
const cargarExpedientes = async () => {
  await store.dispatch('tickets/get');
  fetchDetails();
};

onMounted(cargarExpedientes);

// El panel no se remonta al cambiar de chat (ConversationSidebar lo renderiza con
// v-show y sin :key), solo le cambia el prop. Observamos la identidad de la
// conversacion (no la cantidad de expedientes: dos chats con un expediente cada
// uno no cambiaban la longitud y el refresco no disparaba). conversationId no lo
// tocan las mutaciones de detalle, asi que no hay bucle. No es immediate: el fetch
// inicial ya lo hace onMounted, asi que al montar se pide la lista una sola vez.
watch(() => props.conversationId, cargarExpedientes);

const statusOptions = computed(() =>
  STATUSES.map(status => ({
    value: status,
    label: t(`TICKETS.STATUS.${status.toUpperCase()}`),
  }))
);

const statusDotClass = status => {
  const classes = {
    open: 'bg-n-teal-9',
    pending: 'bg-n-amber-9',
    resolved: 'bg-n-blue-9',
    closed: 'bg-n-slate-9',
  };
  return classes[status] || classes.open;
};

// verde/amarillo/rojo contra los umbrales del ambito PQR (los calcula SEM-01)
const semaforoDotClass = semaforo => {
  const classes = {
    verde: 'bg-n-teal-9',
    amarillo: 'bg-n-amber-9',
    rojo: 'bg-n-ruby-9',
  };
  return classes[semaforo] || '';
};

const clasificacionTexto = ticket =>
  [ticket.tipo?.nombre, ticket.motivo_pqr?.nombre, ticket.categoria?.nombre]
    .filter(Boolean)
    .join(' · ');

const formatFecha = value =>
  value ? new Date(value).toLocaleDateString() : null;

const estaVencido = ticket =>
  typeof ticket.dias_habiles_restantes === 'number' &&
  ticket.dias_habiles_restantes < 0;

const diasVencido = ticket => Math.abs(ticket.dias_habiles_restantes);

// bumping this key remounts the selects so they snap back to the
// real value when the server rejects a change (e.g. no permission)
const selectsRefreshKey = ref(0);

const updateStatus = async (ticket, status) => {
  try {
    await store.dispatch('tickets/update', { id: ticket.id, status });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    selectsRefreshKey.value += 1;
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.UPDATE.FORBIDDEN')
        : t('TICKETS.UPDATE.ERROR')
    );
  }
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <p v-if="!conversationTickets.length" class="text-sm text-n-slate-11">
      {{ t('TICKETS.CONVERSATION.EMPTY') }}
    </p>
    <div
      v-for="ticket in conversationTickets"
      :key="ticket.id"
      class="flex flex-col gap-1.5 p-2 rounded-lg bg-n-alpha-1"
    >
      <div class="flex items-center gap-1.5 min-w-0">
        <span
          class="rounded-full size-2 shrink-0"
          :class="statusDotClass(ticket.status)"
        />
        <p class="min-w-0 mb-0 text-sm font-medium truncate text-n-slate-12">
          {{ ticket.numero_radicado || t('TICKETS.CLOCK.NO_RADICADO') }} ·
          {{ ticket.title }}
        </p>
      </div>

      <p
        v-if="clasificacionTexto(ticket)"
        class="mb-0 text-xs truncate text-n-slate-11"
      >
        {{ clasificacionTexto(ticket) }}
      </p>

      <div
        v-if="ticket.semaforo || ticket.plazo_respuesta_vence_at"
        class="flex flex-wrap items-center gap-x-3 gap-y-1"
      >
        <div
          v-if="ticket.semaforo"
          class="flex items-center gap-1 text-xs"
          :class="ticket.reloj_detenido ? 'opacity-50' : ''"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :class="semaforoDotClass(ticket.semaforo)"
          />
          <span v-if="ticket.reloj_detenido" class="text-n-slate-11">
            {{ t('TICKETS.CLOCK.FROZEN') }}
          </span>
          <span
            v-else-if="estaVencido(ticket)"
            class="font-medium text-n-ruby-11"
          >
            {{ t('TICKETS.CLOCK.OVERDUE', { days: diasVencido(ticket) }) }}
          </span>
          <span v-else class="text-n-slate-11">
            {{
              t('TICKETS.CLOCK.REMAINING', {
                days: ticket.dias_habiles_restantes,
              })
            }}
          </span>
        </div>
        <span
          v-if="ticket.plazo_respuesta_vence_at"
          class="text-xs text-n-slate-11"
        >
          {{
            t('TICKETS.CLOCK.DUE', {
              date: formatFecha(ticket.plazo_respuesta_vence_at),
            })
          }}
        </span>
      </div>

      <Select
        :key="`status-${ticket.id}-${selectsRefreshKey}`"
        :options="statusOptions"
        :model-value="ticket.status"
        @update:model-value="status => updateStatus(ticket, status)"
      />
    </div>
    <Button
      :label="t('TICKETS.CONVERSATION.CREATE')"
      icon="i-lucide-plus"
      sm
      faded
      class="w-full"
      @click="createDialogRef.open()"
    />

    <CreateTicketDialog
      ref="createDialogRef"
      :conversation-id="conversationId"
    />
  </div>
</template>
