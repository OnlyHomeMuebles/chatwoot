<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import GenerarFormatoAPI from 'dashboard/api/helic3/generarFormato';

// FMT-04: modal para generar un formato desde el expediente. Carga los formatos
// con plantilla activa y los items de la garantia; la operadora elige, ve que
// datos faltan, previsualiza con datos reales y confirma. El documento queda en
// «Documentos del caso». El padre lo abre con ref.open().
const props = defineProps({
  ticketId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const cargando = ref(false);
const generando = ref(false);
const formatos = ref([]);
const items = ref([]);
const formatoId = ref(null);
const itemId = ref(null);
const urlPrevia = ref(null);

const itemActual = computed(
  () => items.value.find(it => it.id === itemId.value) || null
);
const formatoActual = computed(
  () => formatos.value.find(f => f.id === formatoId.value) || null
);

// solo se puede generar un formato con plantilla activa y con un item elegido.
const puedeGenerar = computed(
  () => Boolean(formatoActual.value?.plantilla_activa) && Boolean(itemId.value)
);

// faltantes = marcadores que USA la plantilla y que el item tiene VACIOS.
const faltantes = computed(() => {
  const usados = formatoActual.value?.plantilla_activa?.marcadores || [];
  const vacios = itemActual.value?.marcadores_vacios || [];
  return usados.filter(marcador => vacios.includes(marcador));
});

const esSugerido = formato =>
  itemActual.value?.formato_sugerido_id === formato.id;

const limpiarPrevia = () => {
  if (urlPrevia.value) {
    URL.revokeObjectURL(urlPrevia.value);
    urlPrevia.value = null;
  }
};

// preselecciona el formato sugerido por el proceso del item (si tiene plantilla).
const preseleccionarSugerido = () => {
  const sugeridoId = itemActual.value?.formato_sugerido_id;
  const tiene = formatos.value.some(
    f => f.id === sugeridoId && f.plantilla_activa
  );
  formatoId.value = tiene ? sugeridoId : null;
};

const cargar = async () => {
  cargando.value = true;
  try {
    const { data } = await GenerarFormatoAPI.listar(props.ticketId);
    formatos.value = data.formatos || [];
    items.value = data.items || [];
    if (items.value.length === 1) itemId.value = items.value[0].id;
    preseleccionarSugerido();
  } catch (error) {
    useAlert(t('TICKETS.GENERAR_FORMATO.ERROR'));
  } finally {
    cargando.value = false;
  }
};

// al cambiar de item: cambia el sugerido y la previa deja de ser valida.
const alCambiarItem = () => {
  limpiarPrevia();
  preseleccionarSugerido();
};

const elegirFormato = formato => {
  if (!formato.plantilla_activa) return;
  limpiarPrevia();
  formatoId.value = formato.id;
};

const previsualizar = async () => {
  if (!puedeGenerar.value) return;
  try {
    const { data } = await GenerarFormatoAPI.vistaPrevia(props.ticketId, {
      formatoId: formatoId.value,
      itemId: itemId.value,
    });
    limpiarPrevia();
    urlPrevia.value = URL.createObjectURL(data);
  } catch (error) {
    useAlert(t('TICKETS.GENERAR_FORMATO.ERROR'));
  }
};

const cerrar = () => {
  limpiarPrevia();
  formatoId.value = null;
  itemId.value = items.value.length === 1 ? items.value[0].id : null;
  dialogRef.value?.close?.();
};

const confirmar = async () => {
  if (!puedeGenerar.value) return;
  generando.value = true;
  try {
    await GenerarFormatoAPI.generar(props.ticketId, {
      formatoId: formatoId.value,
      itemId: itemId.value,
    });
    // refresca «Documentos del caso» para que aparezca el PDF recien generado.
    await store.dispatch('pqrInbox/fetchDocumentos', props.ticketId);
    useAlert(t('TICKETS.GENERAR_FORMATO.GUARDADO'));
    cerrar();
  } catch (error) {
    // N3 (revision Jhan #116): muestra el mensaje real del servidor (ej. "el
    // formato no tiene una plantilla activa") para que la operadora sepa que
    // hacer; si no viene, cae al mensaje generico.
    useAlert(
      error?.response?.data?.error || t('TICKETS.GENERAR_FORMATO.ERROR')
    );
  } finally {
    generando.value = false;
  }
};

const open = async () => {
  dialogRef.value?.open?.();
  await cargar();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('TICKETS.GENERAR_FORMATO.TITLE')"
    :confirm-button-label="t('TICKETS.GENERAR_FORMATO.GENERAR')"
    :disable-confirm-button="!puedeGenerar"
    :is-loading="generando"
    width="2xl"
    overflow-y-auto
    @confirm="confirmar"
    @close="limpiarPrevia"
  >
    <div v-if="cargando" class="flex justify-center py-6">
      <Spinner />
    </div>

    <p
      v-else-if="items.length === 0"
      data-testid="sin-garantia"
      class="text-sm text-n-slate-11"
    >
      {{ t('TICKETS.GENERAR_FORMATO.SIN_GARANTIA') }}
    </p>

    <div v-else class="flex flex-col gap-4">
      <!-- Elegir producto: solo si la garantia tiene mas de uno -->
      <label v-if="items.length > 1" class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-n-slate-12">
          {{ t('TICKETS.GENERAR_FORMATO.ITEM_LABEL') }}
        </span>
        <select
          v-model="itemId"
          data-testid="select-item"
          class="p-2 border rounded border-n-weak bg-n-alpha-black1"
          @change="alCambiarItem"
        >
          <option v-for="it in items" :key="it.id" :value="it.id">
            {{ it.producto_nombre }}
          </option>
        </select>
      </label>

      <!-- Elegir formato: los sin plantilla activa salen deshabilitados -->
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('TICKETS.GENERAR_FORMATO.FORMATO_LABEL') }}
        </span>
        <button
          v-for="formato in formatos"
          :key="formato.id"
          type="button"
          :data-testid="`formato-${formato.id}`"
          :disabled="!formato.plantilla_activa"
          class="flex flex-col items-start gap-0.5 p-2 text-sm text-left border rounded disabled:opacity-50"
          :class="
            formatoId === formato.id
              ? 'border-n-blue-9 bg-n-alpha-2'
              : 'border-n-weak'
          "
          @click="elegirFormato(formato)"
        >
          <span class="flex items-center gap-2 text-n-slate-12">
            {{ formato.nombre }}
            <span
              v-if="esSugerido(formato)"
              data-testid="badge-sugerido"
              class="px-1.5 py-0.5 text-xs rounded bg-n-blue-3 text-n-blue-11"
            >
              {{ t('TICKETS.GENERAR_FORMATO.SUGERIDO') }}
            </span>
          </span>
          <span
            v-if="!formato.plantilla_activa"
            class="text-xs text-n-slate-10"
          >
            {{ t('TICKETS.GENERAR_FORMATO.SIN_PLANTILLA') }}
          </span>
        </button>
      </div>

      <!-- Datos que faltan para el formato elegido -->
      <div
        v-if="puedeGenerar && faltantes.length"
        data-testid="faltantes"
        class="p-2 text-sm border rounded border-n-amber-6 bg-n-amber-2 text-n-amber-11"
      >
        <p class="font-medium">
          {{ t('TICKETS.GENERAR_FORMATO.FALTANTES_TITLE') }}
        </p>
        <p>{{ faltantes.join(', ') }}</p>
      </div>

      <div v-if="puedeGenerar" class="flex items-center gap-2">
        <Button
          sm
          faded
          :label="t('TICKETS.GENERAR_FORMATO.PREVIEW')"
          data-testid="btn-previa"
          @click="previsualizar"
        />
      </div>

      <iframe
        v-if="urlPrevia"
        :src="urlPrevia"
        data-testid="iframe-previa"
        class="w-full h-[480px] border rounded border-n-weak"
      />
    </div>
  </Dialog>
</template>
