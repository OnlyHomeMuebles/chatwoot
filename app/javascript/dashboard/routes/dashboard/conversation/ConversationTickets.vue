<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CreateTicketDialog from 'dashboard/components/widgets/conversation/CreateTicketDialog.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const STATUSES = ['open', 'pending', 'resolved', 'closed'];

const createDialogRef = ref(null);

const tickets = useMapGetter('tickets/getTickets');
const catalogos = useMapGetter('tickets/getCatalogos');

// props.conversationId es el display_id (lo que Chatwoot expone como id de la
// conversacion en el dashboard). Se compara contra conversation_display_id, no
// contra conversation_id (que es el id de base de datos): así el panel muestra
// también los expedientes que radicó el agente, sin manipular ids del dominio.
const conversationTickets = computed(() =>
  tickets.value.filter(
    ticket => ticket.conversation_display_id === Number(props.conversationId)
  )
);

// el listado omite semaforo/dias (los deriva y encarecerian cada fila); se pide
// el detalle de los pocos tickets de esta conversacion para pintar el semaforo
const fetchDetails = () => {
  conversationTickets.value.forEach(ticket =>
    store.dispatch('tickets/show', ticket.id)
  );
};

// Refresca la LISTA y luego pide el detalle. Volver a pedir la lista es lo que
// hace aparecer un expediente que el agente radico en otra conversacion mientras
// el panel ya estaba abierto: tickets/get corre una sola vez al montar, así que
// sin este refresco ese expediente nunca entraria al store.
const cargarExpedientes = async () => {
  await store.dispatch('tickets/get');
  store.dispatch('tickets/getCatalogos');
  fetchDetails();
};

onMounted(cargarExpedientes);

// El panel no se remonta al cambiar de chat (ConversationSidebar lo renderiza con
// v-show y sin :key), solo le cambia el prop. Observamos la identidad de la
// conversacion (no la cantidad de expedientes: dos chats con un expediente cada
// uno no cambiaban la longitud y el refresco no disparaba). conversationId no lo
// tocan las mutaciones de detalle, asi que no hay bucle. No es immediate: el fetch
// inicial ya lo hace onMounted, asi que al montar se pide la lista una sola vez.
watch(() => props.conversationId, cargarExpedientes);

const statusOptions = computed(() =>
  STATUSES.map(status => ({
    value: status,
    label: t(`TICKETS.STATUS.${status.toUpperCase()}`),
  }))
);

const statusDotClass = status => {
  const classes = {
    open: 'bg-n-teal-9',
    pending: 'bg-n-amber-9',
    resolved: 'bg-n-blue-9',
    closed: 'bg-n-slate-9',
  };
  return classes[status] || classes.open;
};

// verde/amarillo/rojo contra los umbrales del ambito PQR (los calcula SEM-01)
const semaforoDotClass = semaforo => {
  const classes = {
    verde: 'bg-n-teal-9',
    amarillo: 'bg-n-amber-9',
    rojo: 'bg-n-ruby-9',
  };
  return classes[semaforo] || '';
};

// las cuatro filas de clasificacion con su etiqueta; el valor vacio se muestra
// como "Pendiente" (no se oculta: que falte es informacion para el operador).
const clasificacionCampos = ticket => [
  { label: t('TICKETS.FIELDS.CATEGORY'), value: ticket.categoria?.nombre },
  { label: t('TICKETS.FIELDS.TYPE'), value: ticket.tipo?.nombre },
  { label: t('TICKETS.FIELDS.MOTIVE'), value: ticket.motivo_pqr?.nombre },
  { label: t('TICKETS.FIELDS.RESULT'), value: ticket.resultado?.nombre },
];

const formatFecha = value =>
  value ? new Date(value).toLocaleDateString() : null;

// Ancho de la barra del plazo legal: proporcion de tiempo transcurrido entre la
// radicacion y el vencimiento, en dias de CALENDARIO (aritmetica de fechas, no
// reglas de dias habiles: esas las calcula el backend y llegan como texto). Es un
// indicador visual; los numeros oficiales salen del JSON, no de aqui.
const avancePlazo = ticket => {
  if (!ticket.radicada_at || !ticket.plazo_respuesta_vence_at) return 0;

  const inicio = new Date(ticket.radicada_at).getTime();
  const fin = new Date(ticket.plazo_respuesta_vence_at).getTime();
  const ahora = Date.now();
  if (fin <= inicio) return 100;

  const proporcion = ((ahora - inicio) / (fin - inicio)) * 100;
  return Math.min(100, Math.max(0, Math.round(proporcion)));
};

// la barra usa el mismo color del semaforo (fondo con opacidad)
const semaforoBarClass = semaforo => {
  const classes = {
    verde: 'bg-n-teal-9',
    amarillo: 'bg-n-amber-9',
    rojo: 'bg-n-ruby-9',
  };
  return classes[semaforo] || 'bg-n-slate-9';
};

const estaVencido = ticket =>
  typeof ticket.dias_habiles_restantes === 'number' &&
  ticket.dias_habiles_restantes < 0;

const diasVencido = ticket => Math.abs(ticket.dias_habiles_restantes);

// bumping this key remounts the selects so they snap back to the
// real value when the server rejects a change (e.g. no permission)
const selectsRefreshKey = ref(0);

const updateStatus = async (ticket, status) => {
  try {
    await store.dispatch('tickets/update', { id: ticket.id, status });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    selectsRefreshKey.value += 1;
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.UPDATE.FORBIDDEN')
        : t('TICKETS.UPDATE.ERROR')
    );
  }
};

// opciones del selector de resultado, leidas del catalogo (RES-01). Se marca
// con un aviso el que exige aprobacion humana: el operador debe saber que ese
// resultado niega un derecho o mueve dinero.
//
// Candado (GAR-02): mientras no exista el formulario de garantia (que capture
// ciudad y productos), un resultado que abre garantia SIEMPRE falla con 422
// desde el panel —el selector solo manda resultado_id—. Se deshabilita con el
// motivo a la vista en vez de ofrecer un boton que revienta. El agente de IA si
// puede abrirla (AGT-03, lleva los datos); esto es solo la carencia del panel.
const resultadoOptions = computed(() =>
  (catalogos.value.resultados || []).map(resultado => {
    if (resultado.abre_garantia) {
      return {
        value: resultado.id,
        label: `${resultado.nombre} ${t('TICKETS.RESOLUTION.WARRANTY_LOCKED')}`,
        disabled: true,
      };
    }

    return {
      value: resultado.id,
      label: resultado.aprobacion_humana
        ? `${resultado.nombre} ${t('TICKETS.RESOLUTION.NEEDS_APPROVAL')}`
        : resultado.nombre,
    };
  })
);

const resolver = async (ticket, resultadoId) => {
  try {
    await store.dispatch('tickets/resolver', { id: ticket.id, resultadoId });
    useAlert(t('TICKETS.RESOLUTION.SUCCESS'));
  } catch (error) {
    selectsRefreshKey.value += 1;
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.UPDATE.FORBIDDEN')
        : t('TICKETS.RESOLUTION.ERROR')
    );
  }
};

// GAR-03: opciones de proceso para avanzar un producto, leidas de la garantia
// (el serializador las manda con el radicado, ya ordenadas). El proceso terminal
// cierra el radicado; esa regla la aplica el backend, aqui solo se ofrece.
const procesoOptions = garantia =>
  (garantia.procesos || []).map(proceso => ({
    value: proceso.id,
    label: proceso.nombre,
  }));

const avanzarItem = async (garantia, item, procesoId) => {
  try {
    await store.dispatch('tickets/avanzarGarantia', {
      garantiaId: garantia.id,
      itemId: item.id,
      procesoId,
    });
    useAlert(t('TICKETS.WARRANTY.ADVANCED'));
  } catch (error) {
    selectsRefreshKey.value += 1;
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.UPDATE.FORBIDDEN')
        : t('TICKETS.WARRANTY.ERROR')
    );
  }
};

// DAT-01: los campos de texto de la ficha del caso, editables por el operador.
// El detalle tipificado (catalogo) va aparte y de solo lectura: lo deduce la IA.
const DATOS_TEXTO = [
  'cedula',
  'direccion',
  'ciudad',
  'factura_numero',
  'producto_nombre',
];

const datosFuenteLabel = fuente =>
  fuente ? t(`TICKETS.DATA.SOURCE.${fuente.toUpperCase()}`) : '';

// el color del badge dice de un vistazo el origen: IA, ERP o manual
const datosFuenteClass = fuente => {
  const classes = {
    ia: 'bg-n-blue-3 text-n-blue-11',
    erp: 'bg-n-amber-3 text-n-amber-11',
    humano: 'bg-n-teal-3 text-n-teal-11',
  };
  return classes[fuente] || 'bg-n-alpha-2 text-n-slate-10';
};

// al guardar, la fuente de ese campo pasa a humano (lo fija el backend). Un
// valor vacio no se manda: no borra el que habia, misma regla del servicio.
const guardarDato = async (ticket, campo, event) => {
  const valor = event.target.value?.trim();
  if (!valor) return;
  try {
    await store.dispatch('tickets/registrarDatos', {
      id: ticket.id,
      datos: { [campo]: valor },
    });
    useAlert(t('TICKETS.DATA.SAVED'));
  } catch (error) {
    selectsRefreshKey.value += 1;
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.UPDATE.FORBIDDEN')
        : t('TICKETS.DATA.ERROR')
    );
  }
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <p v-if="!conversationTickets.length" class="text-sm text-n-slate-11">
      {{ t('TICKETS.CONVERSATION.EMPTY') }}
    </p>
    <div
      v-for="ticket in conversationTickets"
      :key="ticket.id"
      class="flex flex-col gap-1.5 p-2 rounded-lg bg-n-alpha-1"
    >
      <div class="flex items-center gap-1.5 min-w-0">
        <span
          class="rounded-full size-2 shrink-0"
          :class="statusDotClass(ticket.status)"
        />
        <p class="min-w-0 mb-0 text-sm font-medium truncate text-n-slate-12">
          {{ ticket.numero_radicado || t('TICKETS.CLOCK.NO_RADICADO') }} ·
          {{ ticket.title }}
        </p>
        <!-- Chip de la ETAPA (el estado que ve el cliente). Coexiste con el punto
             de status (estado operativo): son dos cosas distintas a proposito. -->
        <span
          v-if="ticket.etapa"
          class="shrink-0 px-1.5 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
        >
          {{ ticket.etapa.nombre }}
        </span>
      </div>

      <!-- Clasificacion como filas con etiqueta; vacia dice "Pendiente". -->
      <div class="flex flex-col gap-0.5">
        <p
          v-for="campo in clasificacionCampos(ticket)"
          :key="campo.label"
          class="mb-0 text-xs text-n-slate-11"
        >
          <span class="text-n-slate-10">{{ campo.label }}:</span>
          <span v-if="campo.value" class="text-n-slate-12">{{ campo.value }}</span>
          <span v-else class="text-n-slate-10">{{ t('TICKETS.FIELDS.PENDING') }}</span>
        </p>
      </div>

      <!-- Barra del plazo legal: se atenua cuando el reloj esta detenido. -->
      <div
        v-if="ticket.semaforo"
        class="h-1 w-full rounded-full bg-n-alpha-2 overflow-hidden"
        :class="ticket.reloj_detenido ? 'opacity-40' : ''"
      >
        <div
          class="h-full rounded-full"
          :class="semaforoBarClass(ticket.semaforo)"
          :style="{ width: `${avancePlazo(ticket)}%` }"
        />
      </div>

      <div
        v-if="ticket.semaforo || ticket.plazo_respuesta_vence_at"
        class="flex flex-wrap items-center gap-x-3 gap-y-1"
      >
        <div
          v-if="ticket.semaforo"
          class="flex items-center gap-1 text-xs"
          :class="ticket.reloj_detenido ? 'opacity-50' : ''"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :class="semaforoDotClass(ticket.semaforo)"
          />
          <span v-if="ticket.reloj_detenido" class="text-n-slate-11">
            {{ t('TICKETS.CLOCK.FROZEN') }}
          </span>
          <span
            v-else-if="estaVencido(ticket)"
            class="font-medium text-n-ruby-11"
          >
            {{ t('TICKETS.CLOCK.OVERDUE', { days: diasVencido(ticket) }) }}
          </span>
          <span v-else class="text-n-slate-11">
            {{
              t('TICKETS.CLOCK.REMAINING', {
                days: ticket.dias_habiles_restantes,
              })
            }}
          </span>
        </div>
        <span
          v-if="ticket.plazo_respuesta_vence_at"
          class="text-xs text-n-slate-11"
        >
          {{
            t('TICKETS.CLOCK.DUE', {
              date: formatFecha(ticket.plazo_respuesta_vence_at),
            })
          }}
        </span>
      </div>

      <Select
        :key="`status-${ticket.id}-${selectsRefreshKey}`"
        :options="statusOptions"
        :model-value="ticket.status"
        @update:model-value="status => updateStatus(ticket, status)"
      />

      <Select
        :key="`resultado-${ticket.id}-${selectsRefreshKey}`"
        :options="resultadoOptions"
        :model-value="ticket.resultado?.id"
        :placeholder="t('TICKETS.RESOLUTION.PLACEHOLDER')"
        @update:model-value="
          resultadoId => resolver(ticket, resultadoId)
        "
      />

      <!-- Garantia (GAR-02): el radicado que cuelga del expediente. Solo lectura;
           se abre al resolver con "Procede garantia". No se pinta si no hay. -->
      <div
        v-if="ticket.garantia"
        class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-2"
      >
        <p class="mb-0 text-xs font-medium text-n-slate-12">
          {{ t('TICKETS.WARRANTY.TITLE') }}
          {{ ticket.garantia.numero_radicado }}
        </p>
        <p
          v-if="ticket.garantia.proceso_visible"
          class="mb-0 text-xs text-n-slate-11"
        >
          {{ ticket.garantia.proceso_visible.nombre }}
        </p>
        <div class="flex items-center gap-1 text-xs">
          <span
            class="rounded-full size-2 shrink-0"
            :class="semaforoDotClass(ticket.garantia.presupuesto.semaforo)"
          />
          <span class="text-n-slate-11">
            {{
              t('TICKETS.WARRANTY.BUDGET', {
                used: ticket.garantia.presupuesto.consumidos,
                total: ticket.garantia.presupuesto_dias_habiles,
              })
            }}
          </span>
        </div>

        <!-- Cerrada cuando todos los productos resolvieron (GAR-03). -->
        <p
          v-if="ticket.garantia.cerrada_at"
          class="mb-0 text-xs font-medium text-n-teal-11"
        >
          {{ t('TICKETS.WARRANTY.CLOSED') }}
        </p>

        <!-- Un producto por fila con su selector de proceso (GAR-03): moverlo a
             un proceso terminal cierra el radicado si es el ultimo pendiente. -->
        <div
          v-for="item in ticket.garantia.items"
          :key="item.id"
          class="flex items-center gap-1.5"
        >
          <span class="flex-1 min-w-0 text-xs truncate text-n-slate-12">
            {{ item.producto_nombre }}
          </span>
          <Select
            :key="`gitem-${item.id}-${selectsRefreshKey}`"
            :options="procesoOptions(ticket.garantia)"
            :model-value="item.proceso && item.proceso.id"
            :placeholder="t('TICKETS.WARRANTY.PROCESS_PLACEHOLDER')"
            @update:model-value="
              procesoId => avanzarItem(ticket.garantia, item, procesoId)
            "
          />
        </div>
      </div>

      <!-- Datos del caso (DAT-01): cada campo con su badge de procedencia
           (IA/ERP/Manual). Editar un campo lo deja con fuente manual. Vacio se
           muestra como "Pendiente". El detalle tipificado va de solo lectura. -->
      <div
        v-if="ticket.datos"
        class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-2"
      >
        <p class="mb-0 text-xs font-medium text-n-slate-12">
          {{ t('TICKETS.DATA.TITLE') }}
        </p>
        <div
          v-for="campo in DATOS_TEXTO"
          :key="campo"
          class="flex items-center gap-1.5"
        >
          <span class="w-16 text-xs shrink-0 text-n-slate-10">
            {{ t(`TICKETS.DATA.FIELDS.${campo.toUpperCase()}`) }}
          </span>
          <input
            :key="`dato-${campo}-${ticket.id}-${selectsRefreshKey}`"
            :value="ticket.datos[campo] && ticket.datos[campo].valor"
            :placeholder="t('TICKETS.FIELDS.PENDING')"
            class="flex-1 min-w-0 px-1.5 py-0.5 text-xs rounded bg-n-surface-1 outline-1 outline -outline-offset-1 outline-n-weak"
            @change="event => guardarDato(ticket, campo, event)"
          />
          <span
            v-if="ticket.datos[campo] && ticket.datos[campo].fuente"
            class="shrink-0 px-1 py-0.5 rounded text-[10px]"
            :class="datosFuenteClass(ticket.datos[campo].fuente)"
          >
            {{ datosFuenteLabel(ticket.datos[campo].fuente) }}
          </span>
        </div>

        <div
          v-if="ticket.datos.detalle_tipificado"
          class="flex items-center gap-1.5"
        >
          <span class="w-16 text-xs shrink-0 text-n-slate-10">
            {{ t('TICKETS.DATA.FIELDS.DETALLE') }}
          </span>
          <span class="flex-1 min-w-0 text-xs text-n-slate-12">
            {{ ticket.datos.detalle_tipificado.valor.nombre }}
          </span>
          <span
            class="shrink-0 px-1 py-0.5 rounded text-[10px]"
            :class="datosFuenteClass(ticket.datos.detalle_tipificado.fuente)"
          >
            {{ datosFuenteLabel(ticket.datos.detalle_tipificado.fuente) }}
          </span>
        </div>
      </div>
    </div>
    <Button
      :label="t('TICKETS.CONVERSATION.CREATE')"
      icon="i-lucide-plus"
      sm
      faded
      class="w-full"
      @click="createDialogRef.open()"
    />

    <CreateTicketDialog
      ref="createDialogRef"
      :conversation-id="conversationId"
    />
  </div>
</template>
