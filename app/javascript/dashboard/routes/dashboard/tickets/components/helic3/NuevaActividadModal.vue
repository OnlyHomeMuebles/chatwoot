<script setup>
// ACT-01: registra una actividad de seguimiento (una llamada, un WhatsApp, una
// visita a tienda) en el expediente. Titulo y detalle son obligatorios; el autor y
// la fecha los pone el servidor. Al guardar se recarga el expediente para que la
// actividad aparezca arriba en el historial. El padre lo abre con ref.open().
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  ticketId: { type: [Number, String], required: true },
});
// mismos topes que valida Helic3::Actividad en el backend
const TITULO_MAXIMO = 120;
const DETALLE_MAXIMO = 2000;

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const titulo = ref('');
const detalle = ref('');
const guardando = ref(false);
const error = ref('');

const tituloLargo = computed(() => titulo.value.length > TITULO_MAXIMO);
const puedeAgregar = computed(
  () =>
    !!titulo.value.trim() &&
    !!detalle.value.trim() &&
    !tituloLargo.value &&
    detalle.value.length <= DETALLE_MAXIMO
);

const open = () => {
  titulo.value = '';
  detalle.value = '';
  error.value = '';
  dialogRef.value.open();
};

const agregar = async () => {
  // el form del Dialog tambien envia con Enter: no se guarda si falta algo
  if (!puedeAgregar.value) return;
  guardando.value = true;
  error.value = '';
  try {
    await store.dispatch('tickets/crearActividad', {
      ticketId: props.ticketId,
      actividad: { titulo: titulo.value.trim(), detalle: detalle.value.trim() },
    });
    await store.dispatch('pqrInbox/fetchOne', props.ticketId);
    useAlert(t('TICKETS.ACTIVIDAD.SAVED'));
    dialogRef.value.close();
  } catch (e) {
    error.value = e?.response?.data?.message || t('TICKETS.ACTIVIDAD.ERROR');
  } finally {
    guardando.value = false;
  }
};

defineExpose({ open, puedeAgregar });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('TICKETS.ACTIVIDAD.NEW_TITLE')"
    :confirm-button-label="t('TICKETS.ACTIVIDAD.ADD')"
    :disable-confirm-button="!puedeAgregar"
    :is-loading="guardando"
    @confirm="agregar"
  >
    <div class="flex flex-col gap-4">
      <p
        v-if="error"
        data-testid="error"
        class="p-2 mb-0 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
      >
        {{ error }}
      </p>
      <div class="flex flex-col gap-1">
        <Input
          v-model="titulo"
          data-testid="input-titulo"
          :label="t('TICKETS.ACTIVIDAD.TITLE_LABEL')"
          :placeholder="t('TICKETS.ACTIVIDAD.TITLE_PLACEHOLDER')"
          :message="tituloLargo ? t('TICKETS.ACTIVIDAD.TITLE_TOO_LONG') : ''"
          :message-type="tituloLargo ? 'error' : 'info'"
          autofocus
        />
        <span
          class="text-xs text-end tabular-nums"
          :class="tituloLargo ? 'text-n-ruby-11' : 'text-n-slate-10'"
        >
          {{
            t('TICKETS.ACTIVIDAD.CHAR_COUNT', {
              n: titulo.length,
              max: TITULO_MAXIMO,
            })
          }}
        </span>
      </div>
      <TextArea
        v-model="detalle"
        data-testid="input-detalle"
        :label="t('TICKETS.ACTIVIDAD.DETAIL_LABEL')"
        :placeholder="t('TICKETS.ACTIVIDAD.DETAIL_PLACEHOLDER')"
        :max-length="DETALLE_MAXIMO"
        show-character-count
        min-height="6rem"
      />
      <p
        class="px-3 py-2 mb-0 text-sm border border-dashed rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-11"
      >
        {{ t('TICKETS.ACTIVIDAD.AUTHOR_NOTE') }}
      </p>
    </div>
  </Dialog>
</template>
