<script setup>
// GAR-05: formulario con el que un OPERADOR HUMANO abre una garantia desde el
// panel, sin pasar por el agente. Captura la ciudad (una) y uno o varios
// productos (nombre, referencia, motivo y detalle). Al confirmar, llama al MISMO
// endpoint de resolucion que ya existe, con el bloque garantia adjunto. Si el
// backend rechaza, el error se muestra AQUI, en el modal, no como un 422 mudo.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['resolved']);

const store = useStore();
const { t } = useI18n();

const uiFlags = useMapGetter('tickets/getUIFlags');
const catalogos = useMapGetter('tickets/getCatalogos');

const dialogRef = ref(null);
const ticket = ref(null);
const resultadoId = ref(null);
const ciudadId = ref('');
const productos = ref([]);
const error = ref('');

const productoVacio = () => ({
  producto_nombre: '',
  producto_referencia: '',
  motivo_garantia_id: '',
  detalle_tipificado_id: '',
});

// las tres listas del formulario salen del catalogo del panel (GAR-05 las expuso)
const ciudadOptions = computed(() =>
  (catalogos.value.coberturas_ciudad || []).map(c => ({
    value: c.id,
    label: c.nombre,
  }))
);
const motivoOptions = computed(() =>
  (catalogos.value.motivos_garantia || []).map(m => ({
    value: m.id,
    label: m.nombre,
  }))
);
const detalleOptions = computed(() =>
  (catalogos.value.detalles_tipificados || []).map(d => ({
    value: d.id,
    label: d.nombre,
  }))
);

// sin ciudad o con un producto sin nombre no se puede abrir
const puedeConfirmar = computed(
  () =>
    !!ciudadId.value &&
    productos.value.length > 0 &&
    productos.value.every(p => p.producto_nombre)
);

const open = (elTicket, elResultadoId) => {
  ticket.value = elTicket;
  resultadoId.value = elResultadoId;
  ciudadId.value = '';
  productos.value = [productoVacio()];
  error.value = '';
  dialogRef.value.open();
};

const agregarProducto = () => productos.value.push(productoVacio());
const quitarProducto = idx => productos.value.splice(idx, 1);

const abrirGarantia = async () => {
  error.value = '';
  const garantia = {
    cobertura_ciudad_id: ciudadId.value,
    items: productos.value.map(p => ({
      producto_nombre: p.producto_nombre,
      producto_referencia: p.producto_referencia,
      motivo_garantia_id: p.motivo_garantia_id,
      detalle_tipificado_id: p.detalle_tipificado_id,
    })),
  };
  try {
    await store.dispatch('tickets/resolver', {
      id: ticket.value.id,
      resultadoId: resultadoId.value,
      garantia,
    });
    useAlert(t('TICKETS.RESOLUTION.SUCCESS'));
    dialogRef.value.close();
    emit('resolved');
  } catch (e) {
    error.value =
      e?.response?.status === 401
        ? t('TICKETS.UPDATE.FORBIDDEN')
        : e?.response?.data?.error || t('TICKETS.WARRANTY.FORM.ERROR');
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('TICKETS.WARRANTY.FORM.TITLE')"
    :confirm-button-label="t('TICKETS.WARRANTY.FORM.CONFIRM')"
    :is-loading="uiFlags.isUpdating"
    :disable-confirm-button="!puedeConfirmar"
    @confirm="abrirGarantia"
  >
    <div class="flex flex-col gap-4">
      <p
        v-if="error"
        class="p-2 mb-0 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
      >
        {{ error }}
      </p>

      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('TICKETS.WARRANTY.FORM.CITY') }}
        </span>
        <Select
          v-model="ciudadId"
          :options="ciudadOptions"
          :placeholder="t('TICKETS.WARRANTY.FORM.CITY_PLACEHOLDER')"
        />
      </div>

      <div
        v-for="(producto, idx) in productos"
        :key="idx"
        class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1"
      >
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('TICKETS.WARRANTY.FORM.PRODUCT', { n: idx + 1 }) }}
          </span>
          <Button
            v-if="productos.length > 1"
            icon="i-lucide-x"
            xs
            faded
            @click="quitarProducto(idx)"
          />
        </div>
        <Input
          v-model="producto.producto_nombre"
          :placeholder="t('TICKETS.WARRANTY.FORM.PRODUCT_NAME')"
        />
        <Input
          v-model="producto.producto_referencia"
          :placeholder="t('TICKETS.WARRANTY.FORM.PRODUCT_REF')"
        />
        <Select
          v-model="producto.motivo_garantia_id"
          :options="motivoOptions"
          :placeholder="t('TICKETS.WARRANTY.FORM.MOTIVE')"
        />
        <Select
          v-model="producto.detalle_tipificado_id"
          :options="detalleOptions"
          :placeholder="t('TICKETS.WARRANTY.FORM.DETAIL')"
        />
      </div>

      <Button
        :label="t('TICKETS.WARRANTY.FORM.ADD_PRODUCT')"
        icon="i-lucide-plus"
        sm
        faded
        @click="agregarProducto"
      />
    </div>
  </Dialog>
</template>
