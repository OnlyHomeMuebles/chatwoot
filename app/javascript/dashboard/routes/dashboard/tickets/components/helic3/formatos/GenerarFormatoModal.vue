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
// FMT-07: catalogo de marcadores que el operador puede llenar (del backend) y los
// valores que escribe en el modal para ESTE documento (no tocan la base).
const marcadoresEditables = ref({});
const valores = ref({});

const itemActual = computed(
  () => items.value.find(it => it.id === itemId.value) || null
);
const formatoActual = computed(
  () => formatos.value.find(f => f.id === formatoId.value) || null
);

// etiqueta del campo: PRODUCTO se llama "producto original" cuando la plantilla
// tambien pide el producto nuevo (cambio de producto).
const etiquetaDe = (clave, usaNuevo) => {
  if (clave === 'PRODUCTO') {
    return usaNuevo
      ? t('TICKETS.GENERAR_FORMATO.PRODUCTO_ORIGINAL_LABEL')
      : t('TICKETS.GENERAR_FORMATO.PRODUCTO_LABEL');
  }
  if (clave === 'PRODUCTO_DESCRIPCION') return t('TICKETS.GENERAR_FORMATO.DESCRIPCION_LABEL');
  if (clave === 'PRODUCTO_NUEVO') return t('TICKETS.GENERAR_FORMATO.PRODUCTO_NUEVO_LABEL');
  // marcador editable nuevo que el front aun no traduce: usa la etiqueta del backend.
  return marcadoresEditables.value[clave]?.etiqueta || clave;
};

// campos que la operadora llena para el formato elegido: los marcadores editables
// (los declara el backend) que USA su plantilla activa, en el orden del backend.
// input para nombres, textarea para la descripcion.
const camposEditables = computed(() => {
  const usados = formatoActual.value?.plantilla_activa?.marcadores || [];
  const usaNuevo = usados.includes('PRODUCTO_NUEVO');
  return Object.keys(marcadoresEditables.value)
    .filter(clave => usados.includes(clave))
    .map(clave => ({
      clave,
      tipo: marcadoresEditables.value[clave].tipo,
      etiqueta: etiquetaDe(clave, usaNuevo),
    }));
});

// todas las casillas editables de la plantilla deben estar llenas para generar.
const camposCompletos = computed(() =>
  camposEditables.value.every(
    ({ clave }) => (valores.value[clave] || '').trim() !== ''
  )
);

// previsualizar solo necesita plantilla activa y un item: la vista previa SI
// permite casillas vacias (es solo para mirar), como define el backend.
const puedePrevia = computed(
  () => Boolean(formatoActual.value?.plantilla_activa) && Boolean(itemId.value)
);

// generar ademas exige que las casillas obligatorias esten llenas.
const puedeGenerar = computed(
  () => puedePrevia.value && camposCompletos.value
);

// aviso amarillo: SOLO los marcadores que NO se editan aqui (cedula, ciudad...);
// los editables se corrigen en las casillas de arriba, no en «Datos del caso».
const faltantes = computed(() => {
  const usados = formatoActual.value?.plantilla_activa?.marcadores || [];
  const vacios = itemActual.value?.marcadores_vacios || [];
  return usados.filter(
    marcador => vacios.includes(marcador) && !marcadoresEditables.value[marcador]
  );
});

// prellena las casillas: si ya se genero este mismo formato antes, con los valores
// de esa ultima vez; si no, PRODUCTO con el producto del item y el resto vacio.
const sembrarCampos = () => {
  const ultimos = itemActual.value?.ultimos_valores?.[formatoActual.value?.codigo] || {};
  const nuevos = {};
  camposEditables.value.forEach(({ clave }) => {
    if (ultimos[clave]) {
      nuevos[clave] = ultimos[clave];
    } else if (clave === 'PRODUCTO') {
      nuevos[clave] = itemActual.value?.producto_nombre || '';
    } else {
      nuevos[clave] = '';
    }
  });
  valores.value = nuevos;
};

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
    marcadoresEditables.value = data.marcadores_editables || {};
    if (items.value.length === 1) itemId.value = items.value[0].id;
    preseleccionarSugerido();
    sembrarCampos();
  } catch (error) {
    useAlert(t('TICKETS.GENERAR_FORMATO.ERROR'));
  } finally {
    cargando.value = false;
  }
};

// al cambiar de item: cambia el sugerido, resiembra las casillas y la previa caduca.
const alCambiarItem = () => {
  limpiarPrevia();
  preseleccionarSugerido();
  sembrarCampos();
};

const elegirFormato = formato => {
  if (!formato.plantilla_activa) return;
  limpiarPrevia();
  formatoId.value = formato.id;
  // cada formato pide casillas distintas: se recalculan y se prellenan.
  sembrarCampos();
};

const previsualizar = async () => {
  if (!puedePrevia.value) return;
  try {
    const { data } = await GenerarFormatoAPI.vistaPrevia(props.ticketId, {
      formatoId: formatoId.value,
      itemId: itemId.value,
      valoresProducto: valores.value,
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
  valores.value = {};
  dialogRef.value?.close?.();
};

const confirmar = async () => {
  if (!puedeGenerar.value) return;
  generando.value = true;
  try {
    await GenerarFormatoAPI.generar(props.ticketId, {
      formatoId: formatoId.value,
      itemId: itemId.value,
      valoresProducto: valores.value,
    });
    // refresca «Documentos del caso» para que aparezca el formato (.docx) recien generado.
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

      <!-- Casillas del producto que pide este formato (FMT-07): se editan aqui y
           valen SOLO para este documento; el producto de la PQR no cambia. -->
      <div
        v-if="camposEditables.length"
        data-testid="campos-producto"
        class="flex flex-col gap-3 pt-3 border-t border-n-weak"
      >
        <span class="text-xs font-medium tracking-wide uppercase text-n-slate-11">
          {{ t('TICKETS.GENERAR_FORMATO.PRODUCTO_SECCION') }}
        </span>
        <label
          v-for="campo in camposEditables"
          :key="campo.clave"
          class="flex flex-col gap-1 text-sm"
        >
          <span class="font-medium text-n-slate-12">{{ campo.etiqueta }}</span>
          <textarea
            v-if="campo.tipo === 'area'"
            v-model="valores[campo.clave]"
            :data-testid="`campo-${campo.clave}`"
            rows="2"
            class="p-2 text-sm border rounded border-n-weak bg-n-alpha-black1"
            @input="limpiarPrevia"
          />
          <input
            v-else
            v-model="valores[campo.clave]"
            :data-testid="`campo-${campo.clave}`"
            type="text"
            class="p-2 text-sm border rounded border-n-weak bg-n-alpha-black1"
            @input="limpiarPrevia"
          />
        </label>
        <p class="text-xs text-n-slate-10">
          {{ t('TICKETS.GENERAR_FORMATO.SOLO_ESTE_DOC') }}
        </p>
      </div>

      <!-- Datos que faltan para el formato elegido -->
      <div
        v-if="puedePrevia && faltantes.length"
        data-testid="faltantes"
        class="p-2 text-sm border rounded border-n-amber-6 bg-n-amber-2 text-n-amber-11"
      >
        <p class="font-medium">
          {{ t('TICKETS.GENERAR_FORMATO.FALTANTES_TITLE') }}
        </p>
        <p>{{ faltantes.join(', ') }}</p>
      </div>

      <div v-if="puedePrevia" class="flex items-center gap-2">
        <Button
          sm
          faded
          type="button"
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
