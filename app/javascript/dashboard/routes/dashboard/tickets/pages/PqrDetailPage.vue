<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Detalle del expediente (DET-01). Consume el show ya existente
// (GET helic3/tickets/:id) que trae semaforo, dias_habiles_restantes, los sellos
// y la clasificacion. La garantia y el bloque datos son de Samuel: se pintan solo
// si vienen en el payload (nil-safe), no se esperan.
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

// Acciones del operador: cambiar estado y reasignar (registrar el resultado NO es
// de aqui: vive en el panel de conversacion). refreshKey remonta los selectores
// para que vuelvan al valor real si el servidor rechaza el cambio.
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

// Ruta por nombre (no armada a mano): la bandeja.
const volverUrl = computed(() => ({
  name: 'tickets_index',
  params: { accountId: route.params.accountId },
}));

// Barra del presupuesto de garantia: fraccion consumida de los dias habiles.
const garantia = computed(() => expediente.value?.garantia || null);
const presupuestoPct = computed(() => {
  const g = garantia.value;
  if (!g?.presupuesto_dias_habiles) return 0;
  const usado = g.presupuesto?.consumidos ?? 0;
  return Math.min(100, Math.round((usado / g.presupuesto_dias_habiles) * 100));
});
const presupuestoDotClass = computed(
  () =>
    ({
      verde: 'bg-n-teal-9',
      amarillo: 'bg-n-amber-9',
      rojo: 'bg-n-ruby-9',
    })[garantia.value?.presupuesto?.semaforo] || 'bg-n-slate-9'
);

// La PQR de categoria Informacion no tiene plazo legal: no se pinta reloj.
const tieneReloj = computed(
  () =>
    !!expediente.value?.plazo_respuesta_vence_at || !!expediente.value?.semaforo
);

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

const clasificacion = computed(() => {
  const e = expediente.value;
  if (!e) return [];
  return [
    { label: t('TICKETS.DETAIL.TYPE'), valor: e.tipo?.nombre },
    { label: t('TICKETS.DETAIL.MOTIVE'), valor: e.motivo_pqr?.nombre },
    { label: t('TICKETS.DETAIL.CATEGORY'), valor: e.categoria?.nombre },
    { label: t('TICKETS.DETAIL.STAGE'), valor: e.etapa?.nombre },
    { label: t('TICKETS.DETAIL.RESULT'), valor: e.resultado?.nombre },
  ];
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
        <Button icon="i-lucide-arrow-left" ghost sm />
      </router-link>
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('TICKETS.DETAIL.TITLE') }}
      </h1>
    </header>

    <div
      v-if="uiFlags.isFetchingItem"
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

    <div v-else class="flex flex-col max-w-3xl gap-6 p-6 mx-auto w-full">
      <!-- Cabecera del expediente -->
      <section class="flex flex-col gap-1">
        <p class="mb-0 text-sm text-n-slate-11">
          {{ expediente.numero_radicado || t('TICKETS.INBOX.NO_RADICADO') }}
        </p>
        <h2 class="mb-0 text-xl font-medium text-n-slate-12">
          {{ expediente.title }}
        </h2>
      </section>

      <!-- Reloj legal de la PQR (no se pinta en categoria Informacion) -->
      <section
        v-if="tieneReloj"
        class="flex flex-col gap-2 p-4 border rounded-lg border-n-weak"
      >
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('TICKETS.DETAIL.PQR_CLOCK') }}
        </h3>
        <div
          class="flex items-center gap-2"
          :class="expediente.reloj_detenido ? 'opacity-60' : ''"
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
        <dl class="grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
          <div class="flex justify-between">
            <dt class="text-n-slate-11">{{ t('TICKETS.DETAIL.FILED_AT') }}</dt>
            <dd class="mb-0 text-n-slate-12">
              {{ formatFecha(expediente.radicada_at) }}
            </dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-n-slate-11">{{ t('TICKETS.DETAIL.DUE_AT') }}</dt>
            <dd class="mb-0 text-n-slate-12">
              {{ formatFecha(expediente.plazo_respuesta_vence_at) }}
            </dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-n-slate-11">
              {{ t('TICKETS.DETAIL.ANSWERED_AT') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">
              {{ formatFecha(expediente.respondida_at) }}
            </dd>
          </div>
        </dl>
      </section>

      <!-- Clasificacion -->
      <section class="flex flex-col gap-2 p-4 border rounded-lg border-n-weak">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('TICKETS.DETAIL.CLASSIFICATION') }}
        </h3>
        <dl class="flex flex-col gap-1 text-sm">
          <div
            v-for="campo in clasificacion"
            :key="campo.label"
            class="flex justify-between"
          >
            <dt class="text-n-slate-11">{{ campo.label }}</dt>
            <dd class="mb-0 text-n-slate-12">
              {{ campo.valor || t('TICKETS.INBOX.PENDING') }}
            </dd>
          </div>
        </dl>
      </section>

      <!-- Responsable -->
      <section class="flex items-center gap-2 text-sm">
        <span class="text-n-slate-11">{{ t('TICKETS.DETAIL.ASSIGNEE') }}:</span>
        <template v-if="expediente.assignee">
          <Avatar
            :name="expediente.assignee.name"
            :src="expediente.assignee.thumbnail"
            :size="20"
            rounded-full
          />
          <span class="text-n-slate-12">{{ expediente.assignee.name }}</span>
        </template>
        <span v-else class="text-n-slate-11">{{
          t('TICKETS.UNASSIGNED')
        }}</span>
      </section>

      <!-- Acciones del operador: cambiar estado y reasignar. Registrar el resultado
           no va aqui (vive en el panel de conversacion). -->
      <section class="flex flex-wrap items-end gap-4">
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            {{ t('TICKETS.TABLE.STATUS') }}
          </span>
          <Select
            :key="`status-${refreshKey}`"
            :options="statusOptions"
            :model-value="expediente.status"
            class="w-40"
            @update:model-value="cambiarEstado"
          />
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            {{ t('TICKETS.DETAIL.ASSIGNEE') }}
          </span>
          <Select
            :key="`assignee-${refreshKey}`"
            :options="assigneeOptions"
            :model-value="expediente.assignee ? expediente.assignee.id : ''"
            class="w-48"
            @update:model-value="reasignar"
          />
        </div>
      </section>

      <!-- Garantia (contrato de la seccion 3, GAR-02 de Samuel): se pinta contra
           el payload publicado y NO se pinta cuando garantia es null. -->
      <section
        v-if="garantia"
        class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak"
        data-testid="bloque-garantia"
      >
        <div class="flex items-center justify-between">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('TICKETS.DETAIL.WARRANTY') }}
          </h3>
          <span class="text-sm text-n-slate-11">
            {{ garantia.numero_radicado }}
          </span>
        </div>

        <dl class="grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
          <div class="flex justify-between">
            <dt class="text-n-slate-11">{{ t('TICKETS.DETAIL.PROCESS') }}</dt>
            <dd class="mb-0 text-n-slate-12">
              {{ garantia.proceso_visible?.nombre || '—' }}
            </dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-n-slate-11">{{ t('TICKETS.DETAIL.CITY') }}</dt>
            <dd class="mb-0 text-n-slate-12">
              {{ garantia.cobertura_ciudad?.nombre || '—' }}
              <span v-if="garantia.cobertura_ciudad?.tecnico_propio">
                · {{ t('TICKETS.DETAIL.OWN_TECH') }}
              </span>
            </dd>
          </div>
        </dl>

        <!-- Presupuesto: barra con consumidos y saldo sobre los dias habiles -->
        <div v-if="garantia.presupuesto" class="flex flex-col gap-1">
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
            <span>
              {{
                t('TICKETS.DETAIL.BUDGET_USAGE', {
                  used: garantia.presupuesto.consumidos,
                  left: garantia.presupuesto.saldo,
                  total: garantia.presupuesto_dias_habiles,
                })
              }}
            </span>
          </div>
          <div class="w-full h-2 rounded-full bg-n-alpha-2">
            <div
              class="h-2 rounded-full"
              :class="presupuestoDotClass"
              :style="{ width: `${presupuestoPct}%` }"
            />
          </div>
        </div>

        <!-- Items: cada uno con su producto, motivo, detalle y proceso -->
        <div
          v-for="item in garantia.items || []"
          :key="item.id"
          class="flex flex-col gap-0.5 p-2 text-sm rounded bg-n-alpha-1"
        >
          <p class="mb-0 font-medium text-n-slate-12">
            {{ item.producto_nombre }}
            <span v-if="item.producto_referencia" class="text-n-slate-11">
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
      </section>
    </div>
  </div>
</template>
