<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import CreateTicketDialog from 'dashboard/components/widgets/conversation/CreateTicketDialog.vue';

const store = useStore();
const { t } = useI18n();

const STATUSES = ['open', 'pending', 'resolved', 'closed'];

const statusFilter = ref('all');
const showMineOnly = ref(false);
const createDialogRef = ref(null);
const deleteDialogRef = ref(null);
const ticketToDelete = ref(null);

const tickets = useMapGetter('tickets/getTickets');
const uiFlags = useMapGetter('tickets/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const currentUserId = useMapGetter('getCurrentUserID');

onMounted(() => {
  store.dispatch('tickets/get');
  store.dispatch('agents/get');
});

const statusTabs = computed(() => [
  { label: t('TICKETS.FILTERS.ALL'), value: 'all' },
  ...STATUSES.map(status => ({
    label: t(`TICKETS.STATUS.${status.toUpperCase()}`),
    value: status,
  })),
]);

const activeTabIndex = computed(() =>
  statusTabs.value.findIndex(tab => tab.value === statusFilter.value)
);

const onTabChange = tab => {
  statusFilter.value = tab.value;
};

const statusOptions = computed(() =>
  STATUSES.map(status => ({
    value: status,
    label: t(`TICKETS.STATUS.${status.toUpperCase()}`),
  }))
);

const assigneeOptions = computed(() => [
  { value: '', label: t('TICKETS.UNASSIGNED') },
  ...agents.value.map(agent => ({ value: agent.id, label: agent.name })),
]);

const filteredTickets = computed(() => {
  let list = tickets.value;
  if (statusFilter.value !== 'all') {
    list = list.filter(ticket => ticket.status === statusFilter.value);
  }
  if (showMineOnly.value) {
    list = list.filter(
      ticket => ticket.assignee && ticket.assignee.id === currentUserId.value
    );
  }
  return list;
});

const statusDotClass = status => {
  const classes = {
    open: 'bg-n-teal-9',
    pending: 'bg-n-amber-9',
    resolved: 'bg-n-blue-9',
    closed: 'bg-n-slate-9',
  };
  return classes[status] || classes.open;
};

const updateErrorMessage = error =>
  error?.response?.status === 401
    ? t('TICKETS.UPDATE.FORBIDDEN')
    : t('TICKETS.UPDATE.ERROR');

const updateStatus = async (ticket, status) => {
  try {
    await store.dispatch('tickets/update', { id: ticket.id, status });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    useAlert(updateErrorMessage(error));
  }
};

const updateAssignee = async (ticket, assigneeId) => {
  try {
    await store.dispatch('tickets/assign', {
      id: ticket.id,
      assigneeId: assigneeId || null,
    });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    useAlert(updateErrorMessage(error));
  }
};

const openDeleteDialog = ticket => {
  ticketToDelete.value = ticket;
  deleteDialogRef.value.open();
};

const deleteTicket = async () => {
  try {
    await store.dispatch('tickets/delete', ticketToDelete.value.id);
    useAlert(t('TICKETS.DELETE.SUCCESS'));
  } catch (error) {
    const isForbidden = error?.response?.status === 401;
    useAlert(
      isForbidden ? t('TICKETS.DELETE.FORBIDDEN') : t('TICKETS.DELETE.ERROR')
    );
  } finally {
    deleteDialogRef.value.close();
    ticketToDelete.value = null;
  }
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('TICKETS.HEADER') }}
      </h1>
      <Button
        :label="t('TICKETS.NEW_TICKET')"
        icon="i-lucide-plus"
        sm
        @click="createDialogRef.open()"
      />
    </header>

    <div
      class="flex flex-wrap items-center gap-3 px-6 py-3 border-b border-n-weak"
    >
      <TabBar
        :tabs="statusTabs"
        :initial-active-tab="activeTabIndex"
        @tab-changed="onTabChange"
      />
      <label
        class="flex items-center gap-2 ml-auto text-sm cursor-pointer text-n-slate-11"
      >
        <Checkbox v-model="showMineOnly" />
        {{ t('TICKETS.FILTERS.MINE') }}
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
        v-else-if="!filteredTickets.length"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        {{ t('TICKETS.EMPTY_STATE') }}
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-6 py-3 font-medium">
              {{ t('TICKETS.TABLE.NUMBER') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.TABLE.TITLE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.TABLE.STATUS') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.TABLE.ASSIGNEE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.TABLE.CREATED_AT') }}
            </th>
            <th class="px-4 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="ticket in filteredTickets"
            :key="ticket.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-6 py-3 font-medium text-n-slate-12">
              {{ ticket.ticket_number }}
            </td>
            <td class="px-4 py-3">
              <p class="mb-0 font-medium text-n-slate-12">
                {{ ticket.title }}
              </p>
              <p
                v-if="ticket.description"
                class="mb-0 text-n-slate-11 line-clamp-1"
              >
                {{ ticket.description }}
              </p>
            </td>
            <td class="px-4 py-3">
              <div class="flex items-center gap-2">
                <span
                  class="rounded-full size-2 shrink-0"
                  :class="statusDotClass(ticket.status)"
                />
                <Select
                  :options="statusOptions"
                  :model-value="ticket.status"
                  @update:model-value="status => updateStatus(ticket, status)"
                />
              </div>
            </td>
            <td class="px-4 py-3">
              <div class="flex items-center gap-2">
                <Avatar
                  v-if="ticket.assignee"
                  :name="ticket.assignee.name"
                  :src="ticket.assignee.thumbnail"
                  :size="24"
                  rounded-full
                />
                <span
                  v-else
                  class="flex items-center justify-center rounded-full size-6 shrink-0 bg-n-alpha-2"
                >
                  <Icon icon="i-lucide-user" class="size-3.5 text-n-slate-10" />
                </span>
                <Select
                  :options="assigneeOptions"
                  :model-value="ticket.assignee ? ticket.assignee.id : ''"
                  @update:model-value="
                    assigneeId => updateAssignee(ticket, assigneeId)
                  "
                />
              </div>
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ dynamicTime(new Date(ticket.created_at).getTime() / 1000) }}
            </td>
            <td class="px-4 py-3 text-right">
              <Button
                icon="i-lucide-trash-2"
                ghost
                ruby
                xs
                @click="openDeleteDialog(ticket)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CreateTicketDialog ref="createDialogRef" />

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('TICKETS.DELETE.TITLE')"
      :description="t('TICKETS.DELETE.DESCRIPTION')"
      :confirm-button-label="t('TICKETS.DELETE.CONFIRM')"
      :is-loading="uiFlags.isDeleting"
      @confirm="deleteTicket"
    />
  </div>
</template>
