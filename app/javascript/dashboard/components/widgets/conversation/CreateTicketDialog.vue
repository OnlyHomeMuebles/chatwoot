<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  // when present, the created ticket gets linked to this conversation
  conversationId: {
    type: [Number, String],
    default: null,
  },
});

const store = useStore();
const { t } = useI18n();

const STATUSES = ['open', 'pending', 'resolved', 'closed'];

const dialogRef = ref(null);
const newTicket = ref({ title: '', description: '', status: 'open' });

const uiFlags = useMapGetter('tickets/getUIFlags');

const statusOptions = computed(() =>
  STATUSES.map(status => ({
    value: status,
    label: t(`TICKETS.STATUS.${status.toUpperCase()}`),
  }))
);

const open = () => {
  newTicket.value = { title: '', description: '', status: 'open' };
  dialogRef.value.open();
};

const createTicket = async () => {
  if (!newTicket.value.title) return;
  try {
    const ticket = { ...newTicket.value };
    if (props.conversationId) ticket.conversation_id = props.conversationId;
    await store.dispatch('tickets/create', { ticket });
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
      <Input
        v-model="newTicket.title"
        :label="t('TICKETS.CREATE.FORM_TITLE_LABEL')"
        :placeholder="t('TICKETS.CREATE.FORM_TITLE_PLACEHOLDER')"
        autofocus
      />
      <TextArea
        v-model="newTicket.description"
        :label="t('TICKETS.CREATE.FORM_DESCRIPTION_LABEL')"
        :placeholder="t('TICKETS.CREATE.FORM_DESCRIPTION_PLACEHOLDER')"
        :max-length="2000"
        auto-height
      />
      <div class="flex flex-col gap-1">
        <span class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ t('TICKETS.CREATE.FORM_STATUS_LABEL') }}
        </span>
        <Select v-model="newTicket.status" :options="statusOptions" />
      </div>
    </div>
  </Dialog>
</template>
