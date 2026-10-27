<script setup>
// MAN-02: pagina "Nueva PQR manual". Wizard de 2 pasos (Datos del caso +
// Cliente y compra) que radica a mano, sin conversacion, guardando la ficha
// (MAN-01) en un solo POST y luego subiendo los adjuntos. La garantia NO es un
// paso de la creacion: nace al resolver (MAN-03). Estructura tomada del mockup
// v12; estilo con components-next + tokens n-* (como el resto de PQR).
import { computed, reactive, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import TicketsAPI from 'dashboard/api/tickets';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
// ERP-11: consulta del cliente por cedula contra el ERP (ERP-08) para autocompletar.
import { useErpCliente } from '../composables/helic3/useErpCliente';
// ERP-15: selector de facturas + productos del cliente contra el ERP.
import { useErpFacturas } from '../composables/helic3/useErpFacturas';
import ErpBadge from '../components/helic3/ErpBadge.vue';

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const catalogos = useMapGetter('tickets/getCatalogos');
const agents = useMapGetter('agents/getAgents');

const TOTAL_PASOS = 2;
const paso = ref(1);
const errorBackend = ref(''); // mensaje 422 del backend
const errorPaso = ref(''); // validacion del paso actual
const guardando = ref(false);
const adjuntos = ref([]); // [{ id, file }] en memoria hasta crear (id -> :key estable)
let adjuntoSeq = 0; // ids locales incrementales: el nombre+tamano NO es unico (un
// mismo archivo se puede elegir dos veces) y colisionaria como :key
const hoyISO = new Date().toISOString().slice(0, 10); // tope del selector de fecha

const form = reactive({
  tipo_id: null,
  motivo_pqr_id: null,
  detalle_tipificado_id: null,
  description: '',
  assignee_id: null,
  cedula: '',
  cliente_nombre: '',
  cliente_telefono: '',
  cliente_email: '',
  numero_orden: '',
  factura_fecha: '',
  producto_nombre: '',
  producto_referencia: '',
  ciudad: '',
  direccion: '',
});

// Cambio A: el wizard puede abrirse desde una conversacion (boton del chat); el
// display_id llega por query. Entonces la PQR se asocia a esa conversacion y, con
// conversacion, el cliente deja de ser obligatorio (el backend lo toma del contacto).
const conversationDisplayId = route.query.conversation || null;
const vieneDeConversacion = computed(() => !!conversationDisplayId);

// ERP-11: el boton "Consultar Siesa" aparece solo si el ERP esta encendido (ERP-04).
const erp = useErpCliente(form);
const erpHabilitado = computed(() => Boolean(catalogos.value.erp_habilitado));

// ERP-15: una sola accion de "Consultar Siesa" trae el cliente (ERP-11) y sus facturas.
const facturasErp = useErpFacturas(form);
const consultarSiesa = () => {
  erp.consultar();
  facturasErp.consultar(form.cedula);
};
// Cambiar la cedula limpia ambos (no mezclar cliente ni facturas de dos personas).
const alCambiarCedula = () => {
  erp.alCambiarCedula();
  facturasErp.limpiar();
};
const elegirFactura = (factura, item) => facturasErp.elegir(factura, item);

// Aviso segun el resultado de la consulta; ningun estado bloquea "Crear PQR".
const AVISOS_ERP = {
  encontrado: 'TICKETS.NUEVA.CLIENTE.ERP_ENCONTRADO',
  no_encontrado: 'TICKETS.NUEVA.CLIENTE.ERP_NO_ENCONTRADO',
  no_disponible: 'TICKETS.NUEVA.CLIENTE.ERP_NO_DISPONIBLE',
  cedula_invalida: 'TICKETS.NUEVA.CLIENTE.ERP_CEDULA_INVALIDA',
};
const avisoErp = computed(() =>
  AVISOS_ERP[erp.estado.value] ? t(AVISOS_ERP[erp.estado.value]) : ''
);
const avisoErpClase = computed(() =>
  erp.estado.value === 'encontrado' ? 'text-n-teal-11' : 'text-n-amber-11'
);

const opciones = (lista, label = 'nombre') =>
  (lista || []).map(x => ({ value: x.id, label: x[label] }));

const tipoOptions = computed(() => opciones(catalogos.value.tipos));
const motivoOptions = computed(() => opciones(catalogos.value.motivos_pqr));
const detalleOptions = computed(() =>
  opciones(catalogos.value.detalles_tipificados)
);
const responsableOptions = computed(() =>
  (agents.value || []).map(a => ({ value: a.id, label: a.name }))
);

const buscarNombre = (lista, id) =>
  (lista || []).find(x => x.id === id)?.nombre || null;

const tipoNombre = computed(() =>
  buscarNombre(catalogos.value.tipos, form.tipo_id)
);
const motivoNombre = computed(() =>
  buscarNombre(catalogos.value.motivos_pqr, form.motivo_pqr_id)
);
const categoriaDerivada = computed(() => {
  const motivo = (catalogos.value.motivos_pqr || []).find(
    x => x.id === form.motivo_pqr_id
  );
  return motivo?.categoria?.nombre || null;
});
const responsableNombre = computed(
  () => (agents.value || []).find(a => a.id === form.assignee_id)?.name || null
);

onMounted(() => {
  store
    .dispatch('tickets/getCatalogos')
    .catch(() => useAlert(t('TICKETS.CREATE.CATALOGS_ERROR')));
  store.dispatch('agents/get');
});

const onAdjuntos = event => {
  adjuntos.value.push(
    ...Array.from(event.target.files).map(file => {
      adjuntoSeq += 1;
      return { id: adjuntoSeq, file };
    })
  );
  event.target.value = '';
};
const quitarAdjunto = id => {
  adjuntos.value = adjuntos.value.filter(a => a.id !== id);
};

// "Volver" va siempre a la bandeja de PQR (destino determinista; no depende del
// historial del navegador, que con una URL directa o un refresh podria no existir).
const volverABandeja = () =>
  router.push({
    name: 'tickets_index',
    params: { accountId: route.params.accountId },
  });

// Paso 1: motivo y descripcion obligatorios (CA2). Paso 2: cliente y telefono
// (coherente con la validacion de borde de MAN-01 para una PQR sin conversacion).
const validarPaso1 = () => {
  if (!form.motivo_pqr_id) return t('TICKETS.NUEVA.ERRORES.MOTIVO');
  if (!form.description.trim()) return t('TICKETS.NUEVA.ERRORES.DESCRIPCION');
  return '';
};
const validarPaso2 = () => {
  // Con conversacion asociada, el cliente sale del contacto del chat: no se exige
  // reescribirlo (coherente con validar_radicacion_manual! del backend).
  if (vieneDeConversacion.value) return '';
  if (!form.cliente_nombre.trim()) return t('TICKETS.NUEVA.ERRORES.CLIENTE');
  if (!form.cliente_telefono.trim()) return t('TICKETS.NUEVA.ERRORES.TELEFONO');
  return '';
};

const continuar = () => {
  const falla = validarPaso1();
  if (falla) {
    errorPaso.value = falla;
    return;
  }
  errorPaso.value = '';
  paso.value = 2;
};
const anterior = () => {
  errorPaso.value = '';
  paso.value = 1;
};

// Salto por el stepper: solo hacia atras (no se salta adelante sin validar), y
// limpia el error del paso para no arrastrar un mensaje del paso que se deja.
const irAPaso = n => {
  if (n >= paso.value) return;
  errorPaso.value = '';
  paso.value = n;
};

const subirUno = async (ticketId, archivo) => {
  try {
    const formData = new FormData();
    formData.append('archivo', archivo);
    await TicketsAPI.subirDocumento(ticketId, formData);
  } catch (e) {
    useAlert(t('TICKETS.NUEVA.ADJUNTO_FALLO', { nombre: archivo.name }));
  }
};

// uno por uno (secuencial, encadenando promesas: sin for-of ni await-en-bucle). Si
// uno falla, se avisa y se sigue; la PQR ya existe y se navega igual al detalle.
const subirAdjuntos = ticketId =>
  adjuntos.value.reduce(
    (cadena, { file }) => cadena.then(() => subirUno(ticketId, file)),
    Promise.resolve()
  );

const crear = async () => {
  if (guardando.value) return; // evita doble envio (doble clic -> dos radicaciones)
  const fallaPaso1 = validarPaso1();
  if (fallaPaso1) {
    paso.value = 1;
    errorPaso.value = fallaPaso1;
    return;
  }
  const fallaPaso2 = validarPaso2();
  if (fallaPaso2) {
    errorPaso.value = fallaPaso2;
    return;
  }
  errorPaso.value = '';
  errorBackend.value = '';
  guardando.value = true;
  try {
    const title = [motivoNombre.value, form.cliente_nombre]
      .filter(Boolean)
      .join(' · ');
    const payload = {
      ticket: {
        title,
        description: form.description,
        tipo_id: form.tipo_id,
        motivo_pqr_id: form.motivo_pqr_id,
        detalle_tipificado_id: form.detalle_tipificado_id,
        assignee_id: form.assignee_id,
        numero_orden: form.numero_orden || null,
        // display_id de la conversacion si vino del chat (null = PQR manual suelta);
        // el backend lo traduce a id de BD y asocia la PQR.
        conversation_id: conversationDisplayId,
        // ERP-08/11: el backend reconsulta y marca procedencia (erp vs humano) solo si la
        // ultima consulta exitosa fue con la cedula que esta en el campo.
        consultado_erp: erp.consultadoErp(),
        datos: {
          cedula: form.cedula,
          cliente_nombre: form.cliente_nombre,
          cliente_telefono: form.cliente_telefono,
          cliente_email: form.cliente_email,
          ciudad: form.ciudad,
          direccion: form.direccion,
          producto_nombre: form.producto_nombre,
          producto_referencia: form.producto_referencia,
          factura_fecha: form.factura_fecha || null,
        },
      },
    };
    // Pasa por el store (no TicketsAPI directo) para que ADD_TICKET registre la PQR
    // y se maneje isCreating; el store devuelve el ticket creado.
    const ticket = await store.dispatch('tickets/create', payload);
    await subirAdjuntos(ticket.id);
    useAlert(t('TICKETS.NUEVA.CREADA', { consecutivo: ticket.display_id }));
    router.push({
      name: 'helic3_pqr_detail',
      params: { accountId: route.params.accountId, id: ticket.id },
    });
  } catch (e) {
    // El backend usa dos claves: las validaciones de Rails viajan en data.message,
    // pero errores de negocio como la etapa inicial faltante (CAS-01) van en
    // data.error. Se leen ambos para no caer al generico (mismo criterio que el
    // admin de catalogos).
    errorBackend.value =
      e?.response?.data?.message ||
      e?.response?.data?.error ||
      t('TICKETS.NUEVA.ERRORES.GENERAL');
  } finally {
    guardando.value = false;
  }
};

const pasos = computed(() => [
  { n: 1, label: t('TICKETS.NUEVA.PASO1') },
  { n: 2, label: t('TICKETS.NUEVA.PASO2') },
]);

// Superficie para las pruebas (Vitest) del wizard: estado y acciones del flujo.
defineExpose({
  form,
  paso,
  adjuntos,
  errorPaso,
  errorBackend,
  continuar,
  crear,
  volverABandeja,
  erp,
  erpHabilitado,
  avisoErp,
  facturasErp,
  consultarSiesa,
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <!-- Encabezado -->
    <header
      class="flex flex-wrap items-center gap-3 px-6 py-4 border-b border-n-weak shrink-0"
    >
      <div class="flex items-center gap-2">
        <h1 class="mb-0 text-xl font-semibold tracking-tight text-n-slate-12">
          {{ t('TICKETS.NUEVA.TITLE') }}
        </h1>
        <span
          class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-alpha-1 text-n-slate-11"
        >
          {{ t('TICKETS.NUEVA.BADGE') }}
        </span>
      </div>
      <div class="flex-1" />
      <Button
        faded
        color="slate"
        size="sm"
        :label="t('TICKETS.NUEVA.VOLVER')"
        @click="volverABandeja"
      />
    </header>

    <!-- Cuerpo -->
    <div class="flex-1 p-6 overflow-y-auto">
      <div
        class="grid max-w-[85rem] mx-auto gap-6 items-start xl:grid-cols-[minmax(0,1fr)_18rem]"
      >
        <!-- Columna principal -->
        <div class="min-w-0">
          <p class="mb-5 text-sm text-n-slate-11">
            {{ t('TICKETS.NUEVA.SUBTITLE') }}
          </p>

          <!-- Navegacion de pasos -->
          <nav
            class="grid grid-cols-2 gap-2 mb-5"
            :aria-label="t('TICKETS.NUEVA.PASOS_ARIA')"
          >
            <button
              v-for="p in pasos"
              :key="p.n"
              type="button"
              class="flex items-center gap-2.5 px-3 py-3 text-start border rounded-lg"
              :class="
                paso === p.n
                  ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-11'
                  : p.n < paso
                    ? 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1 cursor-pointer'
                    : 'border-n-weak text-n-slate-10 cursor-default'
              "
              @click="irAPaso(p.n)"
            >
              <span
                class="flex items-center justify-center w-6 h-6 text-xs rounded-full shrink-0"
                :class="
                  paso === p.n
                    ? 'bg-n-blue-9 text-white'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{ p.n }}
              </span>
              <span class="text-xs font-medium">{{ p.label }}</span>
            </button>
          </nav>

          <!-- PASO 1: Datos del caso -->
          <section
            v-show="paso === 1"
            class="overflow-hidden border rounded-lg border-n-weak bg-n-solid-1"
          >
            <div class="px-5 py-4 border-b border-n-weak">
              <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
                {{ t('TICKETS.NUEVA.CASO.TITLE') }}
              </h2>
              <p class="mt-1 mb-0 text-xs text-n-slate-11">
                {{ t('TICKETS.NUEVA.CASO.SUBTITLE') }}
              </p>
            </div>
            <div class="flex flex-col gap-5 px-5 py-5">
              <div class="grid gap-5 sm:grid-cols-2">
                <div class="flex flex-col gap-1">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t('TICKETS.NUEVA.CASO.TIPO') }}
                  </span>
                  <Select
                    v-model="form.tipo_id"
                    :options="tipoOptions"
                    :placeholder="t('TICKETS.NUEVA.CASO.TIPO_PH')"
                  />
                </div>
                <div class="flex flex-col gap-1">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t('TICKETS.NUEVA.CASO.MOTIVO') }}
                    <span class="text-n-blue-11">*</span>
                  </span>
                  <Select
                    v-model="form.motivo_pqr_id"
                    :options="motivoOptions"
                    :placeholder="t('TICKETS.NUEVA.CASO.MOTIVO_PH')"
                  />
                  <span
                    v-if="categoriaDerivada"
                    class="text-xs text-n-slate-11"
                  >
                    {{
                      t('TICKETS.CREATE.FORM_CATEGORY_DERIVED', {
                        category: categoriaDerivada,
                      })
                    }}
                  </span>
                </div>
              </div>
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('TICKETS.NUEVA.CASO.DETALLE') }}
                </span>
                <Select
                  v-model="form.detalle_tipificado_id"
                  :options="detalleOptions"
                  :placeholder="t('TICKETS.NUEVA.CASO.DETALLE_PH')"
                />
              </div>
              <TextArea
                v-model="form.description"
                :label="t('TICKETS.NUEVA.CASO.DESCRIPCION')"
                :placeholder="t('TICKETS.NUEVA.CASO.DESCRIPCION_PH')"
                :max-length="2000"
                auto-height
              />
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('TICKETS.NUEVA.CASO.RESPONSABLE') }}
                </span>
                <Select
                  v-model="form.assignee_id"
                  :options="responsableOptions"
                  :placeholder="t('TICKETS.NUEVA.CASO.RESPONSABLE_PH')"
                />
              </div>
              <div class="flex flex-col gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('TICKETS.NUEVA.CASO.ADJUNTOS') }}
                </span>
                <label
                  class="flex flex-col items-center px-4 py-5 text-center border border-dashed rounded-lg cursor-pointer border-n-weak hover:border-n-blue-9"
                >
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t('TICKETS.NUEVA.CASO.ADJUNTOS_CTA') }}
                  </span>
                  <span class="mt-1 text-xs text-n-slate-11">
                    {{ t('TICKETS.NUEVA.CASO.ADJUNTOS_HINT') }}
                  </span>
                  <input
                    type="file"
                    multiple
                    class="sr-only"
                    accept="image/*,.pdf,.doc,.docx"
                    @change="onAdjuntos"
                  />
                </label>
                <div
                  v-for="a in adjuntos"
                  :key="a.id"
                  class="flex items-center gap-3 px-3 py-2 text-xs rounded-lg bg-n-alpha-1"
                >
                  <span class="flex-1 min-w-0 break-words">{{
                    a.file.name
                  }}</span>
                  <button
                    type="button"
                    class="flex text-n-slate-11 hover:text-n-ruby-11"
                    :aria-label="t('TICKETS.NUEVA.CASO.ADJUNTO_QUITAR')"
                    @click="quitarAdjunto(a.id)"
                  >
                    <Icon icon="i-lucide-x" class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            </div>
          </section>

          <!-- PASO 2: Cliente y compra -->
          <div v-show="paso === 2" class="flex flex-col gap-5">
            <section
              class="overflow-hidden border rounded-lg border-n-weak bg-n-solid-1"
            >
              <div class="px-5 py-4 border-b border-n-weak">
                <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
                  {{ t('TICKETS.NUEVA.CLIENTE.TITLE') }}
                </h2>
                <p class="mt-1 mb-0 text-xs text-n-slate-11">
                  {{ t('TICKETS.NUEVA.CLIENTE.SUBTITLE') }}
                </p>
              </div>
              <div class="flex flex-col gap-5 px-5 py-5">
                <!-- Cedula + boton "Consultar Siesa" (solo si el ERP esta encendido). -->
                <div class="flex flex-col gap-1">
                  <span class="mb-0.5 text-heading-3 text-n-slate-12">
                    {{ t('TICKETS.NUEVA.CLIENTE.CEDULA') }}
                  </span>
                  <div class="flex items-start gap-2">
                    <Input
                      v-model="form.cedula"
                      class="flex-1"
                      :placeholder="t('TICKETS.NUEVA.CLIENTE.CEDULA_PH')"
                      @update:model-value="alCambiarCedula()"
                      @keyup.enter="consultarSiesa()"
                    />
                    <Button
                      v-if="erpHabilitado"
                      type="button"
                      :label="t('TICKETS.NUEVA.CLIENTE.CONSULTAR_SIESA')"
                      icon="i-lucide-search"
                      :is-loading="erp.isPending.value"
                      :disabled="!form.cedula"
                      faded
                      @click="consultarSiesa()"
                    />
                  </div>
                  <span v-if="avisoErp" class="text-xs" :class="avisoErpClase">
                    {{ avisoErp }}
                  </span>
                </div>
                <div class="grid gap-5 sm:grid-cols-2">
                  <div class="flex flex-col gap-1">
                    <Input
                      v-model="form.cliente_nombre"
                      :label="`${t('TICKETS.NUEVA.CLIENTE.NOMBRE')} *`"
                      :placeholder="t('TICKETS.NUEVA.CLIENTE.NOMBRE_PH')"
                      @update:model-value="erp.alEditar('cliente_nombre')"
                    />
                    <ErpBadge v-if="erp.tieneBadge('cliente_nombre')" />
                  </div>
                  <div class="flex flex-col gap-1">
                    <Input
                      v-model="form.cliente_telefono"
                      type="tel"
                      :label="`${t('TICKETS.NUEVA.CLIENTE.TELEFONO')} *`"
                      :placeholder="t('TICKETS.NUEVA.CLIENTE.TELEFONO_PH')"
                      @update:model-value="erp.alEditar('cliente_telefono')"
                    />
                    <ErpBadge v-if="erp.tieneBadge('cliente_telefono')" />
                  </div>
                </div>
                <div class="flex flex-col gap-1">
                  <Input
                    v-model="form.cliente_email"
                    type="email"
                    :label="t('TICKETS.NUEVA.CLIENTE.CORREO')"
                    :placeholder="t('TICKETS.NUEVA.CLIENTE.CORREO_PH')"
                    @update:model-value="erp.alEditar('cliente_email')"
                  />
                  <ErpBadge v-if="erp.tieneBadge('cliente_email')" />
                </div>
              </div>
            </section>

            <!-- ERP-15: facturas + productos de Siesa. Al elegir se llenan los campos de
                 "Compra" de abajo; si no esta en la lista, se escriben a mano. Aparece
                 solo cuando la consulta trajo facturas. -->
            <section
              v-if="facturasErp.facturas.value.length"
              class="overflow-hidden border rounded-lg border-n-weak bg-n-solid-1"
            >
              <div class="px-5 py-4 border-b border-n-weak">
                <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
                  {{ t('TICKETS.NUEVA.COMPRA.SELECTOR_TITLE') }}
                </h2>
                <p class="mt-1 mb-0 text-xs text-n-slate-11">
                  {{ t('TICKETS.NUEVA.COMPRA.SELECTOR_HINT') }}
                </p>
              </div>
              <div class="flex flex-col gap-4 px-5 py-5">
                <div
                  v-for="factura in facturasErp.facturas.value"
                  :key="factura.numero"
                  class="border rounded-lg border-n-weak"
                >
                  <div
                    class="flex flex-wrap items-center gap-2 px-4 py-2.5 border-b border-n-weak bg-n-alpha-1"
                  >
                    <span class="text-xs font-semibold text-n-slate-12">{{
                      factura.numero
                    }}</span>
                    <span class="text-xs text-n-slate-11">{{ factura.fecha }}</span>
                    <span
                      v-if="factura.centro_operacion"
                      class="text-xs text-n-slate-11"
                    >
                      · {{ factura.centro_operacion }}
                    </span>
                  </div>
                  <div
                    v-for="item in factura.items"
                    :key="item.referencia"
                    class="flex items-center gap-3 px-4 py-2.5"
                  >
                    <div class="flex-1 min-w-0">
                      <p class="mb-0 text-sm break-words text-n-slate-12">
                        {{ item.descripcion }}
                      </p>
                      <p class="mb-0 text-xs text-n-slate-11">
                        {{ item.referencia }} ·
                        {{ t('TICKETS.NUEVA.COMPRA.SELECTOR_CANT', { n: item.cantidad }) }}
                      </p>
                    </div>
                    <Button
                      type="button"
                      size="sm"
                      faded
                      :label="t('TICKETS.NUEVA.COMPRA.SELECTOR_ELEGIR')"
                      :class="
                        form.numero_orden === factura.numero &&
                        form.producto_referencia === item.referencia
                          ? '!bg-n-blue-3 !text-n-blue-11'
                          : ''
                      "
                      @click="elegirFactura(factura, item)"
                    />
                  </div>
                </div>
              </div>
            </section>

            <section
              class="overflow-hidden border rounded-lg border-n-weak bg-n-solid-1"
            >
              <div class="px-5 py-4 border-b border-n-weak">
                <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
                  {{ t('TICKETS.NUEVA.COMPRA.TITLE') }}
                </h2>
              </div>
              <div class="flex flex-col gap-5 px-5 py-5">
                <div class="grid gap-5 sm:grid-cols-2">
                  <Input
                    v-model="form.numero_orden"
                    :label="t('TICKETS.NUEVA.COMPRA.FACTURA')"
                    :placeholder="t('TICKETS.NUEVA.COMPRA.FACTURA_PH')"
                  />
                  <Input
                    v-model="form.factura_fecha"
                    type="date"
                    :max="hoyISO"
                    :label="t('TICKETS.NUEVA.COMPRA.FECHA')"
                  />
                </div>
                <div class="grid gap-5 sm:grid-cols-2">
                  <Input
                    v-model="form.producto_nombre"
                    :label="t('TICKETS.NUEVA.COMPRA.PRODUCTO')"
                    :placeholder="t('TICKETS.NUEVA.COMPRA.PRODUCTO_PH')"
                  />
                  <Input
                    v-model="form.producto_referencia"
                    :label="t('TICKETS.NUEVA.COMPRA.REFERENCIA')"
                    :placeholder="t('TICKETS.NUEVA.COMPRA.REFERENCIA_PH')"
                  />
                </div>
              </div>
            </section>

            <section
              class="overflow-hidden border rounded-lg border-n-weak bg-n-solid-1"
            >
              <div class="px-5 py-4 border-b border-n-weak">
                <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
                  {{ t('TICKETS.NUEVA.DIRECCION.TITLE') }}
                </h2>
              </div>
              <div class="flex flex-col gap-5 px-5 py-5">
                <div class="flex flex-col gap-1">
                  <Input
                    v-model="form.ciudad"
                    :label="t('TICKETS.NUEVA.DIRECCION.CIUDAD')"
                    :placeholder="t('TICKETS.NUEVA.DIRECCION.CIUDAD_PH')"
                    @update:model-value="erp.alEditar('ciudad')"
                  />
                  <ErpBadge v-if="erp.tieneBadge('ciudad')" />
                </div>
                <div class="flex flex-col gap-1">
                  <Input
                    v-model="form.direccion"
                    :label="t('TICKETS.NUEVA.DIRECCION.DIRECCION')"
                    :placeholder="t('TICKETS.NUEVA.DIRECCION.DIRECCION_PH')"
                    @update:model-value="erp.alEditar('direccion')"
                  />
                  <ErpBadge v-if="erp.tieneBadge('direccion')" />
                </div>
              </div>
            </section>
          </div>

          <!-- Errores cerca del boton de accion: el de validacion de paso y el 422
               del backend. Antes el 422 estaba arriba (lejos del boton Crear) y el
               operador no veia por que fallaba la radicacion. -->
          <div
            v-if="errorPaso || errorBackend"
            class="px-4 py-3 mt-4 text-sm border rounded-lg border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11"
          >
            {{ errorPaso || errorBackend }}
          </div>

          <!-- Pie: navegacion -->
          <div class="flex flex-wrap items-center justify-between gap-3 mt-5">
            <p class="text-xs text-n-slate-11">
              {{ t('TICKETS.NUEVA.PASO_DE', { n: paso, total: TOTAL_PASOS }) }}
              · <span class="text-n-blue-11">*</span>
              {{ t('TICKETS.NUEVA.OBLIGATORIOS') }}
            </p>
            <div class="flex gap-2">
              <Button
                v-if="paso > 1"
                faded
                color="slate"
                :label="t('TICKETS.NUEVA.ANTERIOR')"
                @click="anterior"
              />
              <Button
                v-if="paso < TOTAL_PASOS"
                class="!bg-n-blue-9 hover:!bg-n-blue-10"
                :label="t('TICKETS.NUEVA.CONTINUAR')"
                @click="continuar"
              />
              <Button
                v-else
                class="!bg-n-blue-9 hover:!bg-n-blue-10"
                :label="t('TICKETS.NUEVA.CREAR')"
                :is-loading="guardando"
                :disabled="guardando"
                @click="crear"
              />
            </div>
          </div>
        </div>

        <!-- Resumen lateral -->
        <aside class="xl:sticky xl:top-0">
          <section class="p-5 border rounded-lg border-n-weak bg-n-solid-1">
            <div class="flex items-center justify-between mb-4">
              <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
                {{ t('TICKETS.NUEVA.RESUMEN.TITLE') }}
              </h2>
              <span class="text-xs text-n-slate-11">{{
                t('TICKETS.NUEVA.RESUMEN.BORRADOR')
              }}</span>
            </div>
            <dl class="flex flex-col gap-3 text-xs">
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.RESUMEN.ORIGEN') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ t('TICKETS.NUEVA.RESUMEN.MANUAL') }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.CASO.TIPO') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ tipoNombre || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.RESUMEN.CATEGORIA') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ categoriaDerivada || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.CASO.MOTIVO') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ motivoNombre || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.CASO.RESPONSABLE') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ responsableNombre || '—' }}
                </dd>
              </div>
            </dl>
            <hr class="my-4 border-n-weak" />
            <dl class="flex flex-col gap-3 text-xs">
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.CLIENTE.NOMBRE') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ form.cliente_nombre || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.COMPRA.FACTURA') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ form.numero_orden || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.COMPRA.PRODUCTO') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ form.producto_nombre || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.DIRECCION.CIUDAD') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{ form.ciudad || '—' }}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.NUEVA.CASO.ADJUNTOS') }}
                </dt>
                <dd class="mb-0 text-end text-n-slate-12">
                  {{
                    t(
                      'TICKETS.NUEVA.RESUMEN.ADJUNTOS',
                      { n: adjuntos.length },
                      adjuntos.length
                    )
                  }}
                </dd>
              </div>
            </dl>
          </section>
        </aside>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* MAN-02: los campos van en el beige del lienzo (canvas Nogal), como el mockup
   (control con bg-canvas). Los primitivos de components-next traen su propio fondo
   claro; aqui se unifican al fondo del tema para las tarjetas blancas. El token lo
   remapea el tema Nogal (--background-color), asi que por defecto queda claro. */
:deep(input),
:deep(select),
:deep(textarea) {
  background-color: rgb(var(--background-color));
}
/* Los Select de components-next traen el root con w-fit; en esta pagina deben
   llenar la columna como los Input (full width), segun el mockup. */
:deep(.w-fit.relative),
:deep(.w-fit.relative select) {
  width: 100%;
}
</style>
