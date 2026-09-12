<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Cola de decisiones (DEC-01): lo que el agente propuso y espera a una persona.
// Es la contraparte visible de la autonomía: el agente propone, el humano ejecuta.
// Nada de esta pantalla le escribe al cliente: aprobar solo registra la decisión.
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const decisiones = useMapGetter('pqrInbox/getDecisiones');
const uiFlags = useMapGetter('pqrInbox/getUIFlags');

const cargar = () => store.dispatch('pqrInbox/fetchDecisiones');

onMounted(cargar);

const formatFecha = valor =>
  valor ? new Date(valor).toLocaleDateString() : '—';

const estaVencido = fila =>
  !fila.reloj_detenido &&
  typeof fila.dias_habiles_restantes === 'number' &&
  fila.dias_habiles_restantes < 0;

// Pastilla de estado del reloj por fila: detenido / vencido / vence pronto /
// días restantes, con su color. Deriva del reloj legal que trae el payload.
const estadoTag = fila => {
  if (fila.reloj_detenido) {
    return {
      text: t('TICKETS.DECISIONS.STOPPED'),
      cls: 'bg-n-slate-3 text-n-slate-11',
    };
  }
  if (estaVencido(fila)) {
    return {
      text: t('TICKETS.DECISIONS.OVERDUE', {
        days: Math.abs(fila.dias_habiles_restantes),
      }),
      cls: 'bg-n-ruby-3 text-n-ruby-11',
    };
  }
  if (
    typeof fila.dias_habiles_restantes === 'number' &&
    fila.dias_habiles_restantes <= 1
  ) {
    return {
      text: t('TICKETS.DECISIONS.DUE_SOON'),
      cls: 'bg-n-amber-3 text-n-amber-11',
    };
  }
  if (typeof fila.dias_habiles_restantes === 'number') {
    return {
      text: t('TICKETS.DECISIONS.REMAINING', {
        days: fila.dias_habiles_restantes,
      }),
      cls: 'bg-n-teal-3 text-n-teal-11',
    };
  }
  return { text: '—', cls: 'bg-n-slate-3 text-n-slate-11' };
};

// Sustento derivado del payload real (no un texto inventado): qué propone el
// agente, la regla que lo trajo y que no se le ha escrito al cliente.
const sustento = fila =>
  t('TICKETS.DECISIONS.BASIS', {
    result: fila.propuesta?.nombre || '—',
  });

// Gobernanza: quién puede decidir qué. Reglas del módulo, no un if de código:
// el agente ejecuta lo autónomo; lo que mueve dinero o niega pasa a una persona.
const GOVERNANCE = [
  {
    que: t('TICKETS.DECISIONS.GOV.REPAIR'),
    quien: t('TICKETS.DECISIONS.GOV.AGENT'),
    cls: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    que: t('TICKETS.DECISIONS.GOV.CHANGE'),
    quien: t('TICKETS.DECISIONS.GOV.AGENT'),
    cls: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    que: t('TICKETS.DECISIONS.GOV.REPLACE'),
    quien: t('TICKETS.DECISIONS.GOV.HUMAN'),
    cls: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    que: t('TICKETS.DECISIONS.GOV.REFUND'),
    quien: t('TICKETS.DECISIONS.GOV.HUMAN'),
    cls: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    que: t('TICKETS.DECISIONS.GOV.DENY'),
    quien: t('TICKETS.DECISIONS.GOV.LEGAL'),
    cls: 'bg-n-ruby-3 text-n-ruby-11',
  },
  {
    que: t('TICKETS.DECISIONS.GOV.RETRACT'),
    quien: t('TICKETS.DECISIONS.GOV.HUMAN'),
    cls: 'bg-n-amber-3 text-n-amber-11',
  },
];

// Ver el sustento abre el expediente en el detalle (DET-01). Ruta por nombre; el
// catch evita un rechazo si el detalle aún no está en esta rama de integración.
const verSustento = fila => {
  router
    .push({
      name: 'helic3_pqr_detail',
      params: { accountId: route.params.accountId, id: fila.id },
    })
    .catch(() => {});
};

// Aprobar pide confirmación: aplica un resultado con reloj legal, no es un clic banal.
const dialogoAprobar = ref(null);
const filaAAprobar = ref(null);

const pedirAprobacion = fila => {
  filaAAprobar.value = fila;
  dialogoAprobar.value.open();
};

const aprobar = async () => {
  const fila = filaAAprobar.value;
  dialogoAprobar.value.close();
  if (!fila?.propuesta) return;
  try {
    await store.dispatch('pqrInbox/aprobarDecision', {
      ticketId: fila.id,
      resultadoId: fila.propuesta.id,
    });
    useAlert(t('TICKETS.DECISIONS.APPROVED'));
  } catch (error) {
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.DECISIONS.FORBIDDEN')
        : t('TICKETS.DECISIONS.ERROR')
    );
  }
};

const descripcionAprobar = computed(() =>
  filaAAprobar.value?.propuesta
    ? t('TICKETS.DECISIONS.CONFIRM_DESCRIPTION', {
        result: filaAAprobar.value.propuesta.nombre,
      })
    : ''
);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-y-auto bg-n-background">
    <header
      class="flex flex-wrap items-center gap-3 px-6 py-4 border-b border-n-weak shrink-0"
    >
      <div class="flex flex-col gap-1 min-w-0">
        <h1 class="mb-0 text-xl font-semibold tracking-tight text-n-slate-12">
          {{ t('TICKETS.DECISIONS.TITLE') }}
        </h1>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('TICKETS.DECISIONS.SUBTITLE') }}
        </p>
      </div>
      <div class="flex-1" />
      <span
        v-if="decisiones.length"
        class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-amber-3 text-n-amber-11"
      >
        {{ t('TICKETS.DECISIONS.COUNT', { count: decisiones.length }) }}
      </span>
    </header>

    <div
      v-if="uiFlags.isFetchingDecisiones"
      class="flex items-center justify-center py-12 text-n-slate-11"
    >
      <Spinner :size="24" />
    </div>

    <div v-else class="grid grid-cols-1 gap-6 p-6 lg:grid-cols-3">
      <!-- Columna izquierda: cola de decisiones como tarjetas -->
      <div class="flex flex-col gap-3 lg:col-span-2">
        <div
          v-if="!decisiones.length"
          class="flex items-center justify-center py-12 text-n-slate-11 border rounded-xl border-n-weak"
        >
          {{ t('TICKETS.DECISIONS.EMPTY') }}
        </div>

        <article
          v-for="fila in decisiones"
          :key="fila.id"
          class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-medium tabular-nums text-n-slate-12">
              {{ fila.numero_radicado || t('TICKETS.INBOX.NO_RADICADO') }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ fila.cliente?.nombre || fila.title }}
            </span>
            <span
              class="inline-flex items-center gap-1.5 px-2 py-0.5 ms-auto text-xs font-medium rounded-md"
              :class="estadoTag(fila).cls"
            >
              <span class="rounded-full size-1.5 bg-current" />
              {{ estadoTag(fila).text }}
            </span>
          </div>

          <p class="mb-0 text-sm leading-relaxed text-n-slate-11">
            {{ sustento(fila) }}
          </p>

          <div class="flex flex-wrap items-center gap-2">
            <Button
              :label="t('TICKETS.DECISIONS.APPROVE')"
              color="teal"
              size="sm"
              @click="pedirAprobacion(fila)"
            />
            <Button
              :label="t('TICKETS.DECISIONS.VIEW')"
              variant="faded"
              color="slate"
              size="sm"
              @click="verSustento(fila)"
            />
            <span class="ms-auto text-xs text-n-slate-11">
              {{
                t('TICKETS.DECISIONS.WAITING_AT', {
                  date: formatFecha(fila.propuesto_at),
                })
              }}
            </span>
          </div>

          <div class="pt-2 text-xs border-t text-n-slate-11 border-n-weak">
            {{
              t('TICKETS.DECISIONS.RULE_APPLIED', {
                rule: t('TICKETS.DECISIONS.RULE_HUMAN'),
              })
            }}
          </div>
        </article>
      </div>

      <!-- Columna derecha: quién puede decidir qué -->
      <aside class="flex flex-col gap-4">
        <section
          class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <h2 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('TICKETS.DECISIONS.GOVERNANCE_TITLE') }}
          </h2>
          <ul class="flex flex-col gap-2">
            <li
              v-for="regla in GOVERNANCE"
              :key="regla.que"
              class="flex items-center justify-between gap-2 text-sm"
            >
              <span class="text-n-slate-12">{{ regla.que }}</span>
              <span
                class="px-2 py-0.5 text-xs font-medium rounded-md shrink-0"
                :class="regla.cls"
              >
                {{ regla.quien }}
              </span>
            </li>
          </ul>
          <p
            class="mb-0 p-2.5 text-xs leading-relaxed rounded-lg text-n-amber-11 bg-n-amber-3"
          >
            {{ t('TICKETS.DECISIONS.GOV_NOTE') }}
          </p>
        </section>
      </aside>
    </div>

    <Dialog
      ref="dialogoAprobar"
      :title="t('TICKETS.DECISIONS.CONFIRM_TITLE')"
      :description="descripcionAprobar"
      :confirm-button-label="t('TICKETS.DECISIONS.APPROVE')"
      :is-loading="uiFlags.isFetchingDecisiones"
      @confirm="aprobar"
    />
  </div>
</template>
