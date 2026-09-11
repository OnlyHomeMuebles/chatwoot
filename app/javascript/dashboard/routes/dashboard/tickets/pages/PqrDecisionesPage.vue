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

const relojTexto = fila => {
  if (typeof fila.dias_habiles_restantes !== 'number') return '—';
  return estaVencido(fila)
    ? t('TICKETS.DECISIONS.OVERDUE', {
        days: Math.abs(fila.dias_habiles_restantes),
      })
    : t('TICKETS.DECISIONS.REMAINING', { days: fila.dias_habiles_restantes });
};

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
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('TICKETS.DECISIONS.TITLE') }}
      </h1>
    </header>

    <div class="flex-1 overflow-y-auto">
      <div
        v-if="uiFlags.isFetchingDecisiones"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        <Spinner :size="24" />
      </div>
      <div
        v-else-if="!decisiones.length"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        {{ t('TICKETS.DECISIONS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-6 py-3 font-medium">
              {{ t('TICKETS.DECISIONS.COLUMNS.REFERENCE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.DECISIONS.COLUMNS.PROPOSAL') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.DECISIONS.COLUMNS.RULE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.DECISIONS.COLUMNS.WAITING_SINCE') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('TICKETS.DECISIONS.COLUMNS.CLOCK') }}
            </th>
            <th class="px-4 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="fila in decisiones"
            :key="fila.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-6 py-3">
              <p class="mb-0 font-medium text-n-slate-12">
                {{ fila.numero_radicado || t('TICKETS.INBOX.NO_RADICADO') }}
              </p>
              <p class="mb-0 text-n-slate-11">
                {{ fila.cliente?.nombre || fila.title }}
              </p>
            </td>
            <td class="px-4 py-3 text-n-slate-12">
              {{ fila.propuesta?.nombre || '—' }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ t('TICKETS.DECISIONS.RULE_HUMAN') }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">
              {{ formatFecha(fila.propuesto_at) }}
            </td>
            <td
              class="px-4 py-3"
              :class="
                estaVencido(fila)
                  ? 'text-n-ruby-11 font-medium'
                  : 'text-n-slate-11'
              "
            >
              {{ relojTexto(fila) }}
            </td>
            <td class="px-4 py-3 text-right whitespace-nowrap">
              <Button
                :label="t('TICKETS.DECISIONS.VIEW')"
                faded
                xs
                @click="verSustento(fila)"
              />
              <Button
                :label="t('TICKETS.DECISIONS.APPROVE')"
                sm
                class="ml-2"
                @click="pedirAprobacion(fila)"
              />
            </td>
          </tr>
        </tbody>
      </table>
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
