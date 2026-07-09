<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const { t } = useI18n();

const STATUSES = ['open', 'pending', 'resolved', 'closed'];

const statusFilter = ref('all');
const showMineOnly = ref(false);
const createDialogRef = ref(null);
const deleteDialogRef = ref(null);
const ticketToDelete = ref(null);
const newTicket = ref({ title: '', description: '' });

const tickets = useMapGetter('tickets/getTickets');
const uiFlags = useMapGetter('tickets/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const currentUserId = useMapGetter('getCurrentUserID');

onMounted(() => {
  store.dispatch('tickets/get');
  store.dispatch('agents/get');
});

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

const statusBadgeClass = status => {
  const classes = {
    open: 'bg-n-teal-3 text-n-teal-11',
    pending: 'bg-n-amber-3 text-n-amber-11',
    resolved: 'bg-n-blue-3 text-n-blue-11',
    closed: 'bg-n-slate-3 text-n-slate-11',
  };
  return classes[status] || classes.open;
};

const openCreateDialog = () => {
  newTicket.value = { title: '', description: '' };
  createDialogRef.value.open();
};

const createTicket = async () => {
  if (!newTicket.value.title) return;
  try {
    await store.dispatch('tickets/create', { ticket: newTicket.value });
    useAlert(t('TICKETS.CREATE.SUCCESS'));
    createDialogRef.value.close();
  } catch (error) {
    useAlert(t('TICKETS.CREATE.ERROR'));
  }
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

const updateAssignee = async (ticket, event) => {
  try {
    await store.dispatch('tickets/assign', {
      id: ticket.id,
      assigneeId: event.target.value || null,
    });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    useAlert(t('TICKETS.UPDATE.ERROR'));
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
    useAlert(t('TICKETS.DELETE.ERROR'));
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
        @click="openCreateDialog"
      />
    </header>

    <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
      <button
        class="px-3 py-1 text-sm rounded-lg"
        :class="
          statusFilter === 'all'
            ? 'bg-n-brand/10 text-n-blue-11'
            : 'text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="statusFilter = 'all'"
      >
        {{ t('TICKETS.FILTERS.ALL') }}
      </button>
      <button
        v-for="status in STATUSES"
        :key="status"
        class="px-3 py-1 text-sm rounded-lg"
        :class="
          statusFilter === status
            ? 'bg-n-brand/10 text-n-blue-11'
            : 'text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="statusFilter = status"
      >
        {{ t(`TICKETS.STATUS.${status.toUpperCase()}`) }}
      </button>
      <label
        class="flex items-center gap-1.5 ml-auto text-sm text-n-slate-11 cursor-pointer"
      >
        <input v-model="showMineOnly" type="checkbox" class="cursor-pointer" />
        {{ t('TICKETS.FILTERS.MINE') }}
      </label>
    </div>

    <div class="flex-1 overflow-y-auto">
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        {{ t('TICKETS.LOADING') }}
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
              <p class="font-medium text-n-slate-12">{{ ticket.title }}</p>
              <p v-if="ticket.description" class="text-n-slate-11 line-clamp-1">
                {{ ticket.description }}
              </p>
            </td>
            <td class="px-4 py-3">
              <select
                :value="ticket.status"
                class="px-2 py-1 text-xs font-medium border-0 rounded-lg cursor-pointer"
                :class="statusBadgeClass(ticket.status)"
                @change="updateStatus(ticket, $event)"
              >
                <option
                  v-for="status in STATUSES"
                  :key="status"
                  :value="status"
                >
                  {{ t(`TICKETS.STATUS.${status.toUpperCase()}`) }}
                </option>
              </select>
            </td>
            <td class="px-4 py-3">
              <select
                :value="ticket.assignee ? ticket.assignee.id : ''"
                class="px-2 py-1 text-xs rounded-lg cursor-pointer bg-n-alpha-2 text-n-slate-12 border-0"
                @change="updateAssignee(ticket, $event)"
              >
                <option value="">{{ t('TICKETS.UNASSIGNED') }}</option>
                <option
                  v-for="agent in agents"
                  :key="agent.id"
                  :value="agent.id"
                >
                  {{ agent.name }}
                </option>
              </select>
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

    <Dialog
      ref="createDialogRef"
      :title="t('TICKETS.CREATE.TITLE')"
      :confirm-button-label="t('TICKETS.CREATE.CONFIRM')"
      :is-loading="uiFlags.isCreating"
      :disable-confirm-button="!newTicket.title"
      @confirm="createTicket"
    >
      <div class="flex flex-col gap-4">
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('TICKETS.CREATE.FORM_TITLE_LABEL') }}
          <input
            v-model="newTicket.title"
            type="text"
            class="px-3 py-2 rounded-lg outline-none bg-n-alpha-black2 text-n-slate-12"
            :placeholder="t('TICKETS.CREATE.FORM_TITLE_PLACEHOLDER')"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('TICKETS.CREATE.FORM_DESCRIPTION_LABEL') }}
          <textarea
            v-model="newTicket.description"
            rows="4"
            class="px-3 py-2 rounded-lg outline-none resize-none bg-n-alpha-black2 text-n-slate-12"
            :placeholder="t('TICKETS.CREATE.FORM_DESCRIPTION_PLACEHOLDER')"
          />
        </label>
      </div>
    </Dialog>

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
