<script setup>
import { computed, onMounted, ref } from 'vue';
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

onMounted(() => {
  store.dispatch('tickets/get');
});

const conversationTickets = computed(() =>
  tickets.value.filter(
    ticket => ticket.conversation_id === Number(props.conversationId)
  )
);

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
          {{ ticket.ticket_number }} · {{ ticket.title }}
        </p>
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
