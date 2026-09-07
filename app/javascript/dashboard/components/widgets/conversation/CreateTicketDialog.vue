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

const emptyTicket = () => ({
  title: '',
  description: '',
  status: 'open',
  tipo_id: null,
  motivo_pqr_id: null,
});

const dialogRef = ref(null);
const newTicket = ref(emptyTicket());

const uiFlags = useMapGetter('tickets/getUIFlags');
const catalogos = useMapGetter('tickets/getCatalogos');

const statusOptions = computed(() =>
  STATUSES.map(status => ({
    value: status,
    label: t(`TICKETS.STATUS.${status.toUpperCase()}`),
  }))
);

const tipoOptions = computed(() =>
  catalogos.value.tipos.map(tipo => ({ value: tipo.id, label: tipo.nombre }))
);

// Nota de diseño: el criterio pedía filtrar el motivo por "la categoría del tipo
// elegido", pero los tipos no tienen categoría en el modelo y los motivos no se
// relacionan con tipos. Se ofrecen todos los motivos y la categoría se deriva del
// motivo elegido — la misma derivación que hace Helic3::Casos::Radicar en el back.
const motivoOptions = computed(() =>
  catalogos.value.motivos_pqr.map(motivo => ({
    value: motivo.id,
    label: motivo.nombre,
  }))
);

const categoriaDerivada = computed(() => {
  const motivo = catalogos.value.motivos_pqr.find(
    item => item.id === newTicket.value.motivo_pqr_id
  );
  return motivo?.categoria?.nombre || null;
});

const open = () => {
  newTicket.value = emptyTicket();
  store.dispatch('tickets/getCatalogos');
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
          {{ t('TICKETS.CREATE.FORM_TYPE_LABEL') }}
        </span>
        <Select
          v-model="newTicket.tipo_id"
          :options="tipoOptions"
          :placeholder="t('TICKETS.CREATE.FORM_TYPE_PLACEHOLDER')"
        />
      </div>
      <div class="flex flex-col gap-1">
        <span class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ t('TICKETS.CREATE.FORM_MOTIVE_LABEL') }}
        </span>
        <Select
          v-model="newTicket.motivo_pqr_id"
          :options="motivoOptions"
          :placeholder="t('TICKETS.CREATE.FORM_MOTIVE_PLACEHOLDER')"
        />
        <span v-if="categoriaDerivada" class="text-xs text-n-slate-11">
          {{
            t('TICKETS.CREATE.FORM_CATEGORY_DERIVED', {
              category: categoriaDerivada,
            })
          }}
        </span>
      </div>
      <div class="flex flex-col gap-1">
        <span class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ t('TICKETS.CREATE.FORM_STATUS_LABEL') }}
        </span>
        <Select v-model="newTicket.status" :options="statusOptions" />
      </div>
    </div>
  </Dialog>
</template>
