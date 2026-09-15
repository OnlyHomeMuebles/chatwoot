<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Helic3BudgetBar from 'dashboard/components-next/helic3/Helic3BudgetBar.vue';

// Detalle del expediente (DET-01 + VIS-03). Consume el show (GET helic3/tickets/:id)
// que trae los dos relojes separados (PQR legal y garantia), la clasificacion, los
// datos con procedencia y la garantia con su presupuesto e items. Avanzar de proceso
// reusa tickets/avanzarGarantia (GAR-03): misma llamada del panel, otra vista.
const props = defineProps({
  id: { type: [Number, String], required: true },
});

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const expediente = useMapGetter('pqrInbox/getCurrent');
const uiFlags = useMapGetter('pqrInbox/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const noEncontrado = ref(false);

const STATUSES = ['open', 'pending', 'resolved', 'closed'];

const cargar = async () => {
  noEncontrado.value = false;
  try {
    await store.dispatch('pqrInbox/fetchOne', props.id);
  } catch (error) {
    noEncontrado.value = true;
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  cargar();
});
watch(() => props.id, cargar);

// refreshKey remonta los selectores para que vuelvan al valor real si el servidor
// rechaza el cambio (estado, responsable y avance de proceso).
const refreshKey = ref(0);

const statusOptions = computed(() =>
  STATUSES.map(status => ({
    value: status,
    label: t(`TICKETS.STATUS.${status.toUpperCase()}`),
  }))
);

const assigneeOptions = computed(() => [
  { value: '', label: t('TICKETS.UNASSIGNED') },
  ...agents.value.map(a => ({ value: a.id, label: a.name })),
]);

const errorMsg = error =>
  error?.response?.status === 401
    ? t('TICKETS.UPDATE.FORBIDDEN')
    : t('TICKETS.UPDATE.ERROR');

const cambiarEstado = async status => {
  try {
    await store.dispatch('pqrInbox/actualizar', {
      id: props.id,
      data: { status },
    });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    refreshKey.value += 1;
    useAlert(errorMsg(error));
  }
};

const reasignar = async assigneeId => {
  try {
    await store.dispatch('pqrInbox/asignar', {
      id: props.id,
      assigneeId: assigneeId || null,
    });
    useAlert(t('TICKETS.UPDATE.SUCCESS'));
  } catch (error) {
    refreshKey.value += 1;
    useAlert(errorMsg(error));
  }
};

// Volver a la bandeja conservando los filtros que venian en los query params.
const volverUrl = computed(() => ({
  name: 'tickets_index',
  params: { accountId: route.params.accountId },
  query: route.query,
}));

// Abrir la conversacion de origen: se navega por display_id (lo que Chatwoot
// expone como id de conversacion), no por el id de base de datos.
const conversacionUrl = computed(() =>
  expediente.value?.conversation_display_id
    ? {
        name: 'inbox_conversation',
        params: {
          accountId: route.params.accountId,
          conversation_id: expediente.value.conversation_display_id,
        },
      }
    : null
);

// La clasificacion la propone el agente de IA cuando el expediente nace de un bot
// (origen ia/captain); en ese caso se marca la tarjeta con el badge IA.
const clasificacionEsIA = computed(() =>
  ['ia', 'captain', 'bot'].includes(expediente.value?.origen)
);

const ciudad = computed(() => expediente.value?.datos?.ciudad?.valor || null);

const garantia = computed(() => expediente.value?.garantia || null);
// El % y la barra los calcula el componente compartido Helic3BudgetBar (VIS-04);
// aqui solo queda el color del punto del encabezado.
const presupuestoDotClass = computed(
  () =>
    ({
      verde: 'bg-n-teal-9',
      amarillo: 'bg-n-amber-9',
      rojo: 'bg-n-ruby-9',
    })[garantia.value?.presupuesto?.semaforo] || 'bg-n-slate-9'
);

// La garantia cierra cuando el backend sella cerrada_at (todos los items en un
// proceso terminal). Cerrada: se oculta el selector de avance.
const garantiaCerrada = computed(() => !!garantia.value?.cerrada_at);
const numProductos = computed(() => garantia.value?.items?.length || 0);

// Linea de proceso: el catalogo de procesos activos, marcando el vigente
// (proceso_visible) y el terminal. Sin historial por proceso (eso llega con
// EVT-01 en E4): es la ruta del proceso, no una bitacora.
const procesoTimeline = computed(() => {
  const g = garantia.value;
  if (!g?.procesos) return [];
  const vigenteId = g.proceso_visible?.id;
  return g.procesos.map(p => ({
    id: p.id,
    nombre: p.nombre,
    esVigente: p.id === vigenteId,
    esTerminal: p.es_terminal,
  }));
});

// Procesos destino para el selector de cada producto (catalogo activo).
const procesoOptions = computed(() =>
  (garantia.value?.procesos || []).map(p => ({ value: p.id, label: p.nombre }))
);

const itemEstado = item =>
  item.resuelto_at
    ? {
        text: t('TICKETS.DETAIL.ITEM_RESOLVED'),
        cls: 'bg-n-teal-3 text-n-teal-11',
      }
    : {
        text: t('TICKETS.DETAIL.ITEM_IN_PROGRESS'),
        cls: 'bg-n-blue-3 text-n-blue-11',
      };

// Avanzar un producto de proceso: misma llamada del panel (GAR-03). Al terminar,
// se refresca el expediente con datos del servidor (no se recalcula en cliente).
const avanzarItem = async (item, procesoId) => {
  if (!procesoId || procesoId === item.proceso?.id) return;
  try {
    await store.dispatch('tickets/avanzarGarantia', {
      garantiaId: garantia.value.id,
      itemId: item.id,
      procesoId,
    });
    await store.dispatch('pqrInbox/fetchOne', props.id);
    useAlert(t('TICKETS.WARRANTY.ADVANCED'));
  } catch (error) {
    refreshKey.value += 1;
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.UPDATE.FORBIDDEN')
        : t('TICKETS.WARRANTY.ERROR')
    );
  }
};

// La PQR de categoria Informacion no tiene plazo legal: no se pinta reloj, y no
// genera radicado (queda fuera del conteo frente a la SIC).
const tieneReloj = computed(
  () =>
    !!expediente.value?.plazo_respuesta_vence_at || !!expediente.value?.semaforo
);
const sinRadicado = computed(
  () => !!expediente.value && !expediente.value.numero_radicado
);
const escalamiento = computed(() => expediente.value?.escalamiento || null);

const estaVencido = computed(
  () =>
    !expediente.value?.reloj_detenido &&
    typeof expediente.value?.dias_habiles_restantes === 'number' &&
    expediente.value.dias_habiles_restantes < 0
);

const diasVencido = computed(() =>
  Math.abs(expediente.value?.dias_habiles_restantes ?? 0)
);

const semaforoDotClass = computed(
  () =>
    ({
      verde: 'bg-n-teal-9',
      amarillo: 'bg-n-amber-9',
      rojo: 'bg-n-ruby-9',
    })[expediente.value?.semaforo] || 'bg-n-slate-9'
);

const relojTag = computed(() => {
  if (expediente.value?.reloj_detenido) {
    return {
      text: t('TICKETS.DETAIL.CLOCK_STOPPED'),
      cls: 'bg-n-teal-3 text-n-teal-11',
    };
  }
  if (estaVencido.value) {
    return {
      text: t('TICKETS.DETAIL.CLOCK_OVERDUE_TAG'),
      cls: 'bg-n-ruby-3 text-n-ruby-11',
    };
  }
  const tono =
    {
      verde: 'bg-n-teal-3 text-n-teal-11',
      amarillo: 'bg-n-amber-3 text-n-amber-11',
      rojo: 'bg-n-ruby-3 text-n-ruby-11',
    }[expediente.value?.semaforo] || 'bg-n-slate-3 text-n-slate-11';
  return { text: t('TICKETS.DETAIL.CLOCK_RUNNING'), cls: tono };
});

const clasificacion = computed(() => {
  const e = expediente.value;
  if (!e) return [];
  return [
    {
      label: t('TICKETS.DETAIL.RADICADO'),
      valor: e.numero_radicado,
      mono: true,
    },
    { label: t('TICKETS.DETAIL.CATEGORY'), valor: e.categoria?.nombre },
    { label: t('TICKETS.DETAIL.TYPE'), valor: e.tipo?.nombre },
    { label: t('TICKETS.DETAIL.MOTIVE'), valor: e.motivo_pqr?.nombre },
    { label: t('TICKETS.DETAIL.STAGE'), valor: e.etapa?.nombre },
    { label: t('TICKETS.DETAIL.RESULT'), valor: e.resultado?.nombre },
  ];
});

// Datos del caso con procedencia (DAT-01): cada campo trae { valor, fuente }.
const FUENTES = {
  ia: { label: t('TICKETS.DATA.SOURCE.IA'), cls: 'bg-n-iris-3 text-n-iris-11' },
  erp: {
    label: t('TICKETS.DATA.SOURCE.ERP'),
    cls: 'bg-n-blue-3 text-n-blue-11',
  },
  humano: {
    label: t('TICKETS.DATA.SOURCE.HUMANO'),
    cls: 'bg-n-slate-3 text-n-slate-11',
  },
};
const badgeFuente = fuente => FUENTES[fuente] || null;

const datosLista = computed(() => {
  const d = expediente.value?.datos || {};
  const campos = [
    { key: 'cedula', label: t('TICKETS.DATA.FIELDS.CEDULA') },
    { key: 'direccion', label: t('TICKETS.DATA.FIELDS.DIRECCION') },
    { key: 'ciudad', label: t('TICKETS.DATA.FIELDS.CIUDAD') },
    { key: 'factura_numero', label: t('TICKETS.DATA.FIELDS.FACTURA_NUMERO') },
    { key: 'producto_nombre', label: t('TICKETS.DATA.FIELDS.PRODUCTO_NOMBRE') },
  ];
  const filas = campos.map(c => ({
    label: c.label,
    valor: d[c.key]?.valor ?? null,
    fuente: d[c.key]?.fuente ?? null,
  }));
  filas.push({
    label: t('TICKETS.DATA.FIELDS.DETALLE'),
    valor: d.detalle_tipificado?.valor?.nombre ?? null,
    fuente: d.detalle_tipificado?.fuente ?? null,
  });
  return filas;
});

const siguienteAccion = computed(() => {
  if (expediente.value?.reloj_detenido) return t('TICKETS.DETAIL.NEXT_FROZEN');
  if (garantia.value) {
    return t('TICKETS.DETAIL.NEXT_WARRANTY', {
      process: garantia.value.proceso_visible?.nombre || '—',
    });
  }
  return t('TICKETS.DETAIL.NEXT_ANSWER');
});

// Actividad: linea de tiempo con los sellos reales del expediente. NO se inventan
// eventos. EVT-01 (bitacora) la reemplaza en E4 con la traza completa por evento.
const actividad = computed(() => {
  const e = expediente.value;
  if (!e) return [];
  return [
    { at: e.radicada_at, titulo: t('TICKETS.DETAIL.ACT_FILED') },
    {
      at: garantia.value?.abierta_at,
      titulo: t('TICKETS.DETAIL.ACT_WARRANTY'),
    },
    { at: e.respondida_at, titulo: t('TICKETS.DETAIL.ACT_ANSWERED') },
    { at: e.cerrada_at, titulo: t('TICKETS.DETAIL.ACT_CLOSED') },
  ]
    .filter(h => h.at)
    .map((h, i, arr) => ({ ...h, ultimo: i === arr.length - 1 }));
});

// Documentos: el formato del proceso vigente (su generacion aun no existe: la
// descarga queda deshabilitada). Las evidencias del cliente llegan con FMT/EVT.
const documentos = computed(() => {
  const proceso = garantia.value?.proceso_visible?.nombre;
  if (!proceso) return [];
  return [{ nombre: t('TICKETS.DETAIL.DOC_FORMAT', { process: proceso }) }];
});

const formatFecha = valor =>
  valor ? new Date(valor).toLocaleDateString() : '—';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-y-auto bg-n-background">
    <header
      class="flex items-center gap-3 px-6 py-4 border-b border-n-weak shrink-0"
    >
      <router-link :to="volverUrl">
        <Button
          icon="i-lucide-arrow-left"
          :label="t('TICKETS.DETAIL.BACK')"
          variant="ghost"
          color="slate"
          size="sm"
        />
      </router-link>
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('TICKETS.DETAIL.TITLE') }}
      </h1>
    </header>

    <div
      v-if="uiFlags.isFetchingItem && !expediente"
      class="flex items-center justify-center py-16 text-n-slate-11"
    >
      <Spinner :size="24" />
    </div>

    <div
      v-else-if="noEncontrado || !expediente"
      class="flex flex-col items-center justify-center gap-2 py-16 text-n-slate-11"
    >
      <Icon icon="i-lucide-file-question" class="size-8 text-n-slate-9" />
      {{ t('TICKETS.DETAIL.NOT_FOUND') }}
    </div>

    <div v-else class="flex flex-col w-full max-w-6xl gap-6 p-6 mx-auto">
      <!-- Cabecera del expediente: radicado, subtitulo y abrir conversacion -->
      <section class="flex flex-wrap items-end gap-3">
        <div class="flex flex-col gap-1 min-w-0">
          <h2 class="mb-0 text-xl font-semibold tracking-tight text-n-slate-12">
            {{ expediente.numero_radicado || t('TICKETS.INBOX.NO_RADICADO') }}
          </h2>
          <p class="mb-0 text-sm text-n-slate-11">
            {{
              [expediente.title, ciudad, expediente.assignee?.name]
                .filter(Boolean)
                .join(' · ')
            }}
          </p>
        </div>
        <div class="flex-1" />
        <router-link v-if="conversacionUrl" :to="conversacionUrl">
          <Button
            icon="i-lucide-messages-square"
            :label="t('TICKETS.DETAIL.OPEN_CONVERSATION')"
            variant="outline"
            color="slate"
            size="sm"
          />
        </router-link>
      </section>

      <!-- Avisos de reglas legales -->
      <section
        v-if="sinRadicado"
        class="flex items-start gap-2 p-3 text-sm rounded-lg text-n-blue-11 bg-n-blue-3"
      >
        <Icon icon="i-lucide-info" class="mt-0.5 size-4 shrink-0" />
        {{ t('TICKETS.DETAIL.INFO_NOTICE') }}
      </section>
      <section
        v-if="escalamiento"
        class="flex items-start gap-2 p-3 text-sm rounded-lg text-n-amber-11 bg-n-amber-3"
      >
        <Icon icon="i-lucide-triangle-alert" class="mt-0.5 size-4 shrink-0" />
        {{
          t('TICKETS.DETAIL.ESCALATION_NOTICE', { escalation: escalamiento })
        }}
      </section>

      <div class="grid grid-cols-1 gap-6 min-[1100px]:grid-cols-3">
        <!-- Columna izquierda: expediente legal + garantia -->
        <div class="flex flex-col gap-6 min-[1100px]:col-span-2">
          <!-- PQR · expediente legal -->
          <section
            class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                  {{ t('TICKETS.DETAIL.LEGAL_TITLE') }}
                </h3>
                <span
                  v-if="clasificacionEsIA"
                  class="px-1.5 py-0.5 text-[10px] font-semibold tracking-wide rounded bg-n-iris-3 text-n-iris-11"
                >
                  {{ t('TICKETS.DATA.SOURCE.IA') }}
                </span>
              </div>
              <span
                class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium rounded-md"
                :class="relojTag.cls"
              >
                <span class="rounded-full size-1.5 bg-current" />
                {{ relojTag.text }}
              </span>
            </div>

            <dl
              class="grid grid-cols-1 text-sm gap-x-6 gap-y-1.5 sm:grid-cols-2"
            >
              <div
                v-for="campo in clasificacion"
                :key="campo.label"
                class="flex justify-between gap-3"
              >
                <dt class="text-n-slate-11 shrink-0">{{ campo.label }}</dt>
                <dd
                  class="mb-0 text-right text-n-slate-12"
                  :class="campo.mono ? 'tabular-nums' : ''"
                >
                  {{ campo.valor || t('TICKETS.INBOX.PENDING') }}
                </dd>
              </div>
            </dl>

            <!-- Reloj legal de la PQR (15 dias habiles SIC) -->
            <div
              v-if="tieneReloj"
              class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1"
            >
              <div
                class="flex items-center gap-2"
                :class="expediente.reloj_detenido ? 'opacity-70' : ''"
              >
                <span
                  class="rounded-full size-2.5 shrink-0"
                  :class="semaforoDotClass"
                />
                <span
                  v-if="expediente.reloj_detenido"
                  class="text-sm text-n-slate-11"
                >
                  {{
                    t('TICKETS.DETAIL.CLOCK_FROZEN', {
                      days: expediente.dias_habiles_restantes,
                    })
                  }}
                </span>
                <span
                  v-else-if="estaVencido"
                  class="text-sm font-medium text-n-ruby-11"
                >
                  {{ t('TICKETS.DETAIL.CLOCK_OVERDUE', { days: diasVencido }) }}
                </span>
                <span v-else class="text-sm text-n-slate-11">
                  {{
                    t('TICKETS.DETAIL.CLOCK_REMAINING', {
                      days: expediente.dias_habiles_restantes,
                    })
                  }}
                </span>
              </div>
              <dl
                class="grid grid-cols-1 text-sm sm:grid-cols-3 gap-x-6 gap-y-1"
              >
                <div class="flex justify-between gap-2">
                  <dt class="text-n-slate-11">
                    {{ t('TICKETS.DETAIL.FILED_AT') }}
                  </dt>
                  <dd class="mb-0 text-n-slate-12">
                    {{ formatFecha(expediente.radicada_at) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-2">
                  <dt class="text-n-slate-11">
                    {{ t('TICKETS.DETAIL.DUE_AT') }}
                  </dt>
                  <dd class="mb-0 text-n-slate-12">
                    {{ formatFecha(expediente.plazo_respuesta_vence_at) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-2">
                  <dt class="text-n-slate-11">
                    {{ t('TICKETS.DETAIL.ANSWERED_AT') }}
                  </dt>
                  <dd class="mb-0 text-n-slate-12">
                    {{ formatFecha(expediente.respondida_at) }}
                  </dd>
                </div>
              </dl>
            </div>
          </section>

          <!-- Garantia (GAR-02/03): expediente operativo, reloj de 30 dias habiles -->
          <section
            v-if="garantia"
            class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1"
            data-testid="bloque-garantia"
          >
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                  {{ t('TICKETS.DETAIL.WARRANTY') }}
                </h3>
                <span class="text-sm tabular-nums text-n-slate-11">
                  {{ garantia.numero_radicado }}
                </span>
              </div>
              <span
                v-if="garantiaCerrada"
                class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-teal-3 text-n-teal-11"
              >
                {{ t('TICKETS.WARRANTY.CLOSED') }}
              </span>
              <span
                v-else-if="garantia.proceso_visible"
                class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-blue-3 text-n-blue-11"
              >
                {{ garantia.proceso_visible.nombre }}
              </span>
            </div>

            <dl
              class="grid grid-cols-1 text-sm gap-x-6 gap-y-1.5 sm:grid-cols-2"
            >
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">{{ t('TICKETS.DETAIL.CITY') }}</dt>
                <dd class="mb-0 text-right text-n-slate-12">
                  {{ garantia.cobertura_ciudad?.nombre || '—' }}
                  <span v-if="garantia.cobertura_ciudad?.tecnico_propio">
                    · {{ t('TICKETS.DETAIL.OWN_TECH') }}
                  </span>
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.DETAIL.ASSIGNEE') }}
                </dt>
                <dd class="mb-0 text-right text-n-slate-12">
                  {{ expediente.assignee?.name || t('TICKETS.UNASSIGNED') }}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">
                  {{ t('TICKETS.DETAIL.PRODUCTS') }}
                </dt>
                <dd class="mb-0 text-right tabular-nums text-n-slate-12">
                  {{ numProductos }}
                </dd>
              </div>
            </dl>

            <!-- Presupuesto: barra con consumidos y saldo sobre los dias habiles -->
            <div v-if="garantia.presupuesto" class="flex flex-col gap-1.5">
              <div
                class="flex items-center justify-between text-xs text-n-slate-11"
              >
                <span class="flex items-center gap-1.5">
                  <span
                    class="rounded-full size-2 shrink-0"
                    :class="presupuestoDotClass"
                  />
                  {{ t('TICKETS.DETAIL.BUDGET') }}
                </span>
                <span class="tabular-nums">
                  {{
                    t('TICKETS.DETAIL.BUDGET_USAGE', {
                      used: garantia.presupuesto.consumidos,
                      left: garantia.presupuesto.saldo,
                      total: garantia.presupuesto_dias_habiles,
                    })
                  }}
                </span>
              </div>
              <Helic3BudgetBar
                :consumidos="garantia.presupuesto.consumidos"
                :total="garantia.presupuesto_dias_habiles"
                :semaforo="garantia.presupuesto.semaforo"
                hide-label
              />
            </div>

            <!-- Linea de proceso -->
            <div v-if="procesoTimeline.length" class="flex flex-col gap-2">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('TICKETS.DETAIL.TIMELINE') }}
              </span>
              <ol class="flex flex-col gap-2">
                <li
                  v-for="paso in procesoTimeline"
                  :key="paso.id"
                  class="flex items-center gap-2.5 text-sm"
                >
                  <span
                    class="rounded-full size-2 shrink-0"
                    :class="paso.esVigente ? 'bg-n-brand' : 'bg-n-slate-6'"
                  />
                  <span
                    :class="
                      paso.esVigente
                        ? 'font-medium text-n-slate-12'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ paso.nombre }}
                  </span>
                  <span
                    v-if="paso.esTerminal"
                    class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-n-slate-3 text-n-slate-10"
                  >
                    {{ t('TICKETS.DETAIL.STEP_TERMINAL') }}
                  </span>
                </li>
              </ol>
            </div>

            <!-- Productos del radicado, con estado y selector de proceso destino -->
            <div class="flex flex-col gap-2">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('TICKETS.DETAIL.PRODUCTS') }}
              </span>
              <div
                v-for="item in garantia.items || []"
                :key="item.id"
                class="flex flex-col gap-2 p-2.5 text-sm rounded-lg bg-n-alpha-1"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="flex flex-col gap-0.5 min-w-0">
                    <p class="mb-0 font-medium text-n-slate-12">
                      {{ item.producto_nombre }}
                      <span
                        v-if="item.producto_referencia"
                        class="text-n-slate-11"
                      >
                        · {{ item.producto_referencia }}
                      </span>
                    </p>
                    <p class="mb-0 text-xs text-n-slate-11">
                      {{
                        [
                          item.motivo_garantia?.nombre,
                          item.detalle_tipificado?.nombre,
                          item.proceso?.nombre,
                        ]
                          .filter(Boolean)
                          .join(' · ')
                      }}
                    </p>
                  </div>
                  <span
                    class="px-2 py-0.5 text-xs font-medium rounded-md shrink-0"
                    :class="itemEstado(item).cls"
                  >
                    {{ itemEstado(item).text }}
                  </span>
                </div>
                <!-- Avanzar de proceso: misma llamada del panel (GAR-03). Solo si
                     la garantia no esta cerrada. -->
                <Select
                  v-if="!garantiaCerrada && procesoOptions.length"
                  :key="`proc-${item.id}-${refreshKey}`"
                  :options="procesoOptions"
                  :model-value="item.proceso?.id ?? ''"
                  :placeholder="t('TICKETS.WARRANTY.PROCESS_PLACEHOLDER')"
                  @update:model-value="
                    procesoId => avanzarItem(item, procesoId)
                  "
                />
              </div>
              <p v-if="!garantiaCerrada" class="mb-0 text-xs text-n-amber-11">
                {{ t('TICKETS.DETAIL.BUDGET_NO_RESET') }}
              </p>
            </div>
          </section>

          <!-- Aviso cuando la PQR no abrio garantia (abre_garantia: nunca) -->
          <section
            v-else
            class="flex items-center gap-2 p-3 text-sm rounded-lg text-n-slate-11 bg-n-alpha-1"
          >
            <Icon
              icon="i-lucide-shield-off"
              class="size-4 text-n-slate-9 shrink-0"
            />
            {{ t('TICKETS.DETAIL.NO_WARRANTY') }}
          </section>
        </div>

        <!-- Columna derecha: siguiente accion, acciones, datos, actividad y documentos -->
        <div class="flex flex-col gap-6">
          <section
            class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('TICKETS.DETAIL.NEXT_ACTION') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">{{ siguienteAccion }}</p>
          </section>

          <section
            class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('TICKETS.DETAIL.OPERATOR_ACTIONS') }}
            </h3>
            <div class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">{{
                t('TICKETS.TABLE.STATUS')
              }}</span>
              <Select
                :key="`status-${refreshKey}`"
                :options="statusOptions"
                :model-value="expediente.status"
                @update:model-value="cambiarEstado"
              />
            </div>
            <div class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">{{
                t('TICKETS.DETAIL.ASSIGNEE')
              }}</span>
              <Select
                :key="`assignee-${refreshKey}`"
                :options="assigneeOptions"
                :model-value="expediente.assignee ? expediente.assignee.id : ''"
                @update:model-value="reasignar"
              />
            </div>
          </section>

          <!-- Datos del caso con procedencia (badges IA / ERP / Manual) -->
          <section
            class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('TICKETS.DATA.TITLE') }}
            </h3>
            <dl class="flex flex-col gap-2 text-sm">
              <div
                v-for="dato in datosLista"
                :key="dato.label"
                class="flex flex-col gap-0.5"
              >
                <dt class="text-xs text-n-slate-11">{{ dato.label }}</dt>
                <dd class="flex items-center gap-2 mb-0 text-n-slate-12">
                  <template v-if="dato.valor">
                    <span class="min-w-0 break-words">{{ dato.valor }}</span>
                    <span
                      v-if="badgeFuente(dato.fuente)"
                      class="px-1.5 py-0.5 text-[10px] font-semibold tracking-wide rounded shrink-0"
                      :class="badgeFuente(dato.fuente).cls"
                    >
                      {{ badgeFuente(dato.fuente).label }}
                    </span>
                  </template>
                  <span v-else class="text-n-slate-11">
                    {{ t('TICKETS.INBOX.PENDING') }}
                  </span>
                </dd>
              </div>
            </dl>
          </section>

          <!-- Actividad: sellos reales (EVT-01 la reemplaza en E4) -->
          <section
            v-if="actividad.length"
            class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('TICKETS.DETAIL.ACTIVITY') }}
            </h3>
            <ol class="flex flex-col gap-3">
              <li
                v-for="hito in actividad"
                :key="hito.titulo"
                class="flex gap-2.5"
              >
                <span
                  class="mt-1 rounded-full size-2 shrink-0"
                  :class="hito.ultimo ? 'bg-n-brand' : 'bg-n-teal-9'"
                />
                <div class="flex flex-col gap-0.5 min-w-0">
                  <span class="text-sm text-n-slate-12">{{ hito.titulo }}</span>
                  <span class="text-xs text-n-slate-11">
                    {{ formatFecha(hito.at) }}
                  </span>
                </div>
              </li>
            </ol>
          </section>

          <!-- Documentos: formato del proceso vigente (generacion pendiente) -->
          <section
            class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('TICKETS.DETAIL.DOCUMENTS') }}
            </h3>
            <div
              v-for="doc in documentos"
              :key="doc.nombre"
              class="flex items-center justify-between gap-2 p-2.5 text-sm rounded-lg bg-n-alpha-1"
            >
              <span class="min-w-0 break-words text-n-slate-12">
                {{ doc.nombre }}
              </span>
              <span
                v-tooltip="t('TICKETS.DETAIL.DOC_DISABLED')"
                class="inline-flex"
              >
                <Button
                  icon="i-lucide-download"
                  variant="faded"
                  color="slate"
                  size="xs"
                  disabled
                />
              </span>
            </div>
            <p class="mb-0 text-xs text-n-slate-10">
              {{ t('TICKETS.DETAIL.DOC_EVIDENCE_NOTE') }}
            </p>
          </section>
        </div>
      </div>
    </div>
  </div>
</template>
