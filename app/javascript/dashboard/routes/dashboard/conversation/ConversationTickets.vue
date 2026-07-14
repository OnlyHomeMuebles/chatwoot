<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
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

onMounted(() => {
  store.dispatch('tickets/get');
});

const conversationTickets = computed(() =>
  tickets.value.filter(
    ticket => ticket.conversation_id === Number(props.conversationId)
  )
);

const statusBadgeClass = status => {
  const classes = {
    open: 'bg-n-teal-3 text-n-teal-11',
    pending: 'bg-n-amber-3 text-n-amber-11',
    resolved: 'bg-n-blue-3 text-n-blue-11',
    closed: 'bg-n-slate-3 text-n-slate-11',
  };
  return classes[status] || classes.open;
};

const updateStatus = async (ticket, event) => {
  try {
    await store.dispatch('tickets/update', {
      id: ticket.id,
      status: event.target.value,
    });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    useAlert(t('TICKETS.UPDATE.ERROR'));
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
      class="flex items-center justify-between gap-2 p-2 rounded-lg bg-n-alpha-1"
    >
      <p class="min-w-0 text-sm font-medium truncate text-n-slate-12">
        {{ ticket.ticket_number }} · {{ ticket.title }}
      </p>
      <select
        :value="ticket.status"
        class="px-2 py-1 text-xs font-medium border-0 rounded-lg cursor-pointer shrink-0"
        :class="statusBadgeClass(ticket.status)"
        @change="updateStatus(ticket, $event)"
      >
        <option v-for="status in STATUSES" :key="status" :value="status">
          {{ t(`TICKETS.STATUS.${status.toUpperCase()}`) }}
        </option>
      </select>
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
