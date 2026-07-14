<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const STATUSES = ['open', 'pending', 'resolved', 'closed'];

const dialogRef = ref(null);
const newTicket = ref({ title: '', description: '', status: 'open' });

const uiFlags = useMapGetter('tickets/getUIFlags');

const open = () => {
  newTicket.value = { title: '', description: '', status: 'open' };
  dialogRef.value.open();
};

const createTicket = async () => {
  if (!newTicket.value.title) return;
  try {
    await store.dispatch('tickets/create', {
      ticket: { ...newTicket.value, conversation_id: props.conversationId },
    });
    useAlert(t('TICKETS.CREATE.SUCCESS'));
    dialogRef.value.close();
  } catch (error) {
    useAlert(t('TICKETS.CREATE.ERROR'));
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
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
          rows="3"
          class="px-3 py-2 rounded-lg outline-none resize-none bg-n-alpha-black2 text-n-slate-12"
          :placeholder="t('TICKETS.CREATE.FORM_DESCRIPTION_PLACEHOLDER')"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('TICKETS.CREATE.FORM_STATUS_LABEL') }}
        <select
          v-model="newTicket.status"
          class="px-3 py-2 rounded-lg outline-none cursor-pointer bg-n-alpha-black2 text-n-slate-12"
        >
          <option v-for="status in STATUSES" :key="status" :value="status">
            {{ t(`TICKETS.STATUS.${status.toUpperCase()}`) }}
          </option>
        </select>
      </label>
    </div>
  </Dialog>
</template>
