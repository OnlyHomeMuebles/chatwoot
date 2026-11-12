<script setup>
// GAR-05: formulario con el que un OPERADOR HUMANO abre una garantia desde el
// panel, sin pasar por el agente. Captura la ciudad (una) y uno o varios
// productos (nombre, referencia y motivo). Al confirmar, llama al MISMO endpoint
// de resolucion que ya existe, con el bloque garantia adjunto. Si el backend
// rechaza, el error se muestra AQUI, en el modal, no como un 422 mudo.
//
// GAR-07: a pedido de Karen, el detalle tipificado se vuelve a pedir aqui, por
// producto (GAR-06 lo habia quitado). Es un catalogo AUTONOMO (CAT-02): sale de la
// descripcion y las fotos, no del motivo (la misma falla puede darse bajo motivos
// distintos), asi que se ofrecen TODOS, sin filtrar. El backend ya lo acepta por item
// (si no viene, hereda el de la ficha). No se abre sin ciudad, sin motivo ni sin detalle.
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
const contexto = ref({});
const error = ref('');

// desdePqr: el producto viene de la ficha (o del ERP) y se muestra de solo lectura.
const productoVacio = () => ({
  producto_nombre: '',
  producto_referencia: '',
  motivo_garantia_id: '',
  detalle_tipificado_id: '',
  desdePqr: false,
});

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

// GAR-07: catalogo autonomo (CAT-02), se ofrecen todos los detalles (sin filtrar
// por motivo: la asociacion es opcional y de apoyo, nunca una pertenencia).
const detalleOptions = computed(() =>
  (catalogos.value.detalles_tipificados || []).map(d => ({
    value: d.id,
    label: d.nombre,
  }))
);

// Ayuda bajo la ciudad: con que proceso arranca la garantia (el nombre sale del catalogo).
const ayudaCiudad = computed(() => {
  const ciudad = (catalogos.value.coberturas_ciudad || []).find(
    c => c.id === ciudadId.value
  );
  if (!ciudad?.proceso_inicial_nombre) return '';
  const proceso = ciudad.proceso_inicial_nombre;
  return ciudad.tecnico_propio
    ? t('TICKETS.WARRANTY.FORM.CITY_HELP_TECH', { proceso })
    : t('TICKETS.WARRANTY.FORM.CITY_HELP_NO_TECH', { proceso });
});

// "PQR #11 · cliente · resultado elegido": solo las partes que se conocen.
const subtitulo = computed(() => {
  const { radicado, cliente, resultado } = contexto.value;
  return [
    radicado && t('TICKETS.WARRANTY.FORM.HEADER_PQR', { radicado }),
    cliente,
    resultado,
  ]
    .filter(Boolean)
    .join(' · ');
});

// Lo primero que falta, para deshabilitar el boton y decirlo debajo.
const faltante = computed(() => {
  if (!ciudadId.value) return t('TICKETS.WARRANTY.FORM.MISSING_CITY');
  const idxNombre = productos.value.findIndex(p => !p.producto_nombre.trim());
  if (idxNombre >= 0) {
    return t('TICKETS.WARRANTY.FORM.MISSING_NAME', { n: idxNombre + 1 });
  }
  const idxMotivo = productos.value.findIndex(p => !p.motivo_garantia_id);
  if (idxMotivo >= 0) {
    return t('TICKETS.WARRANTY.FORM.MISSING_MOTIVE', { n: idxMotivo + 1 });
  }
  // GAR-07: el detalle se pide por producto; sin el, la garantia quedaria sin
  // [DETALLE] en el PDF ni en Indicadores.
  const idxDetalle = productos.value.findIndex(p => !p.detalle_tipificado_id);
  if (idxDetalle >= 0) {
    return t('TICKETS.WARRANTY.FORM.MISSING_DETAIL', { n: idxDetalle + 1 });
  }
  return '';
});

const puedeConfirmar = computed(
  () => productos.value.length > 0 && !faltante.value
);

const resumen = computed(() =>
  productos.value.length === 1
    ? t('TICKETS.WARRANTY.FORM.SUMMARY_ONE')
    : t('TICKETS.WARRANTY.FORM.SUMMARY_OTHER', { n: productos.value.length })
);

// Normaliza para cruzar la ciudad de la ficha (texto libre: "armenia", "Armenía")
// con el nombre del catalogo ("Armenia"): sin acentos, sin espacios extremos, en
// minusculas. Asi el precargado acierta aunque el operador no escriba igual.
const normalizar = s =>
  (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').trim().toLowerCase();

// Tercer argumento opcional (MAN-03/GAR-06): precarga y contexto desde el expediente.
// { productos, producto_nombre, producto_referencia, ciudad_nombre, detalle_nombre,
//   radicado, cliente_nombre, resultado_nombre }. Quien llame con dos argumentos (el
// chat sin datos) obtiene una tarjeta editable y el comportamiento de siempre.
const open = (elTicket, elResultadoId, prefill = {}) => {
  ticket.value = elTicket;
  resultadoId.value = elResultadoId;
  const resultado = (catalogos.value.resultados || []).find(
    r => r.id === elResultadoId
  );
  contexto.value = {
    radicado: prefill.radicado || elTicket?.numero_radicado || '',
    cliente: prefill.cliente_nombre || '',
    resultado: prefill.resultado_nombre || resultado?.nombre || '',
  };
  // La ficha guarda la ciudad como texto; el form usa el id del catalogo. Se
  // traduce por nombre normalizado; si no hay cobertura equivalente, queda vacia y
  // la elige el operador (nunca se envia un id inventado).
  const ciudadBuscada = normalizar(prefill.ciudad_nombre);
  const ciudad = (catalogos.value.coberturas_ciudad || []).find(
    c => normalizar(c.nombre) === ciudadBuscada
  );
  ciudadId.value = ciudad?.id || '';
  // ERP-15: una tarjeta por producto de la ficha; si no hay lista, el producto unico de la
  // ficha; si tampoco hay, una tarjeta editable vacia (el caso del chat).
  const lista = Array.isArray(prefill.productos) ? prefill.productos : [];
  if (lista.length) {
    productos.value = lista.map(p => ({
      ...productoVacio(),
      producto_nombre: p.nombre || '',
      producto_referencia: p.referencia || '',
      desdePqr: true,
    }));
  } else if (prefill.producto_nombre) {
    productos.value = [
      {
        ...productoVacio(),
        producto_nombre: prefill.producto_nombre,
        producto_referencia: prefill.producto_referencia || '',
        desdePqr: true,
      },
    ];
  } else {
    productos.value = [productoVacio()];
  }
  error.value = '';
  dialogRef.value.open();
};

const agregarProducto = () => productos.value.push(productoVacio());
const quitarProducto = idx => productos.value.splice(idx, 1);

const abrirGarantia = async () => {
  // el form del Dialog tambien envia con Enter: no se abre si falta algo
  if (!puedeConfirmar.value) return;
  error.value = '';
  const garantia = {
    cobertura_ciudad_id: ciudadId.value,
    items: productos.value.map(p => ({
      producto_nombre: p.producto_nombre.trim(),
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

// `productos`, `ciudadId`, `faltante` y `puedeConfirmar` se exponen para las pruebas.
defineExpose({
  open,
  productos,
  ciudadId,
  faltante,
  puedeConfirmar,
  detalleOptions,
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="t('TICKETS.WARRANTY.FORM.TITLE')"
    :description="subtitulo"
    :confirm-button-label="t('TICKETS.WARRANTY.FORM.CONFIRM')"
    :is-loading="uiFlags.isUpdating"
    :disable-confirm-button="!puedeConfirmar"
    @confirm="abrirGarantia"
  >
    <div class="flex flex-col gap-6">
      <p
        v-if="error"
        class="p-2 mb-0 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
      >
        {{ error }}
      </p>

      <!-- Cobertura -->
      <section class="flex flex-col gap-3">
        <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
          {{ t('TICKETS.WARRANTY.FORM.SECTION_COVERAGE') }}
        </h4>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('TICKETS.WARRANTY.FORM.CITY') }}
          </span>
          <Select
            v-model="ciudadId"
            data-testid="select-ciudad"
            class="!w-full [&>select]:w-full"
            :options="ciudadOptions"
            :placeholder="t('TICKETS.WARRANTY.FORM.CITY_PLACEHOLDER')"
          />
          <span v-if="ayudaCiudad" class="text-xs text-n-slate-11">
            {{ ayudaCiudad }}
          </span>
        </label>
      </section>

      <!-- Productos en garantia -->
      <section class="flex flex-col gap-3">
        <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
          {{
            t('TICKETS.WARRANTY.FORM.SECTION_PRODUCTS', { n: productos.length })
          }}
        </h4>

        <div
          v-for="(producto, idx) in productos"
          :key="idx"
          data-testid="tarjeta-producto"
          class="flex flex-col gap-3 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex flex-col min-w-0 gap-0.5">
              <template v-if="producto.desdePqr">
                <span
                  data-testid="producto-nombre"
                  class="text-sm font-semibold truncate text-n-slate-12"
                >
                  {{ producto.producto_nombre }}
                </span>
                <span
                  v-if="producto.producto_referencia"
                  class="text-xs text-n-slate-11"
                >
                  {{
                    t('TICKETS.WARRANTY.FORM.REF', {
                      ref: producto.producto_referencia,
                    })
                  }}
                </span>
              </template>
              <span
                class="self-start px-1.5 py-0.5 mt-1 text-xs rounded"
                :class="
                  producto.desdePqr
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-slate-3 text-n-slate-11'
                "
              >
                {{
                  producto.desdePqr
                    ? t('TICKETS.WARRANTY.FORM.FROM_PQR')
                    : t('TICKETS.WARRANTY.FORM.MANUAL')
                }}
              </span>
            </div>
            <Button
              v-if="productos.length > 1"
              data-testid="btn-quitar"
              icon="i-lucide-trash-2"
              :label="t('TICKETS.WARRANTY.FORM.REMOVE')"
              xs
              faded
              slate
              @click="quitarProducto(idx)"
            />
          </div>

          <template v-if="!producto.desdePqr">
            <Input
              v-model="producto.producto_nombre"
              data-testid="input-nombre"
              :label="t('TICKETS.WARRANTY.FORM.PRODUCT_NAME')"
              :placeholder="t('TICKETS.WARRANTY.FORM.PRODUCT_NAME_PLACEHOLDER')"
            />
            <Input
              v-model="producto.producto_referencia"
              :label="t('TICKETS.WARRANTY.FORM.PRODUCT_REF')"
            />
          </template>

          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('TICKETS.WARRANTY.FORM.MOTIVE') }}
            </span>
            <Select
              v-model="producto.motivo_garantia_id"
              data-testid="select-motivo"
              class="!w-full [&>select]:w-full"
              :options="motivoOptions"
              :placeholder="t('TICKETS.WARRANTY.FORM.MOTIVE_PLACEHOLDER')"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('TICKETS.WARRANTY.FORM.DETAIL') }}
            </span>
            <Select
              v-model="producto.detalle_tipificado_id"
              data-testid="select-detalle"
              class="!w-full [&>select]:w-full"
              :options="detalleOptions"
              :placeholder="t('TICKETS.WARRANTY.FORM.DETAIL_PLACEHOLDER')"
            />
          </label>
        </div>

        <Button
          class="self-start"
          :label="t('TICKETS.WARRANTY.FORM.ADD_PRODUCT')"
          icon="i-lucide-plus"
          sm
          faded
          @click="agregarProducto"
        />
      </section>

      <!-- Resumen y lo que falta, justo encima de los botones del pie -->
      <div class="flex flex-col gap-1 pt-3 border-t border-n-weak">
        <p data-testid="resumen" class="mb-0 text-sm text-n-slate-12">
          {{ resumen }}
        </p>
        <p
          v-if="faltante"
          data-testid="faltante"
          class="mb-0 text-xs text-n-ruby-11"
        >
          {{ faltante }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
