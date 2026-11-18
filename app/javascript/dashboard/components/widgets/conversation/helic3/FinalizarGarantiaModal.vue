<script setup>
// GAR-08: modal de la observacion de cierre de una garantia. Generico: lo usan el
// expediente y el panel del chat para los tres casos (finalizar, agregar a una
// cerrada antes del despliegue, editar). El padre decide QUE hacer al confirmar
// (avanzar el producto que cierra, o anexar sobre una cerrada) pasando onConfirm;
// este modal solo exige el texto y reporta error o cancelacion. El texto es
// obligatorio (sin contar espacios), maximo 1000 caracteres.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const OBSERVACION_MAXIMA = 1000;

const { t } = useI18n();

const dialogRef = ref(null);
const observacion = ref('');
const titulo = ref('');
const guardando = ref(false);
const error = ref('');
const exito = ref(false);
let alConfirmar = null;
let alCancelar = null;

const puedeConfirmar = computed(
  () =>
    !!observacion.value.trim() && observacion.value.length <= OBSERVACION_MAXIMA
);

// onConfirm(texto) -> Promise; onCancel() opcional (p.ej. revertir el selector).
const open = ({ texto = '', title = '', onConfirm, onCancel } = {}) => {
  observacion.value = texto;
  titulo.value = title || t('TICKETS.GARANTIA_CIERRE.TITLE');
  error.value = '';
  exito.value = false;
  alConfirmar = onConfirm;
  alCancelar = onCancel;
  dialogRef.value.open();
};

const confirmar = async () => {
  // el form del Dialog tambien envia con Enter: no confirma si falta texto
  if (!puedeConfirmar.value || !alConfirmar) return;
  guardando.value = true;
  error.value = '';
  try {
    await alConfirmar(observacion.value.trim());
    exito.value = true;
    dialogRef.value.close();
  } catch (e) {
    error.value =
      e?.response?.data?.error ||
      e?.response?.data?.message ||
      t('TICKETS.GARANTIA_CIERRE.ERROR');
  } finally {
    guardando.value = false;
  }
};

// el Dialog se cerro (cancelar, clic fuera o Esc): si no fue por un confirm
// exitoso, es cancelacion -> el padre revierte lo que haya mostrado el selector.
const alCerrar = () => {
  if (!exito.value && alCancelar) alCancelar();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="titulo"
    :confirm-button-label="t('TICKETS.GARANTIA_CIERRE.CONFIRM')"
    :disable-confirm-button="!puedeConfirmar"
    :is-loading="guardando"
    @confirm="confirmar"
    @close="alCerrar"
  >
    <div class="flex flex-col gap-4">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('TICKETS.GARANTIA_CIERRE.HINT') }}
      </p>
      <p
        v-if="error"
        data-testid="error"
        class="p-2 mb-0 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
      >
        {{ error }}
      </p>
      <TextArea
        v-model="observacion"
        data-testid="input-observacion"
        :label="t('TICKETS.GARANTIA_CIERRE.LABEL')"
        :placeholder="t('TICKETS.GARANTIA_CIERRE.PLACEHOLDER')"
        :max-length="OBSERVACION_MAXIMA"
        show-character-count
        min-height="6rem"
        autofocus
      />
    </div>
  </Dialog>
</template>
