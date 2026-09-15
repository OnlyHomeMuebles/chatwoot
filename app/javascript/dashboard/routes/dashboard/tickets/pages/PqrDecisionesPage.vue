<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Cola de decisiones (DEC-01) + regla que la justifica (DEC-02): lo que el agente
// propuso y espera a una persona, con QUIEN puede firmar cada resultado al lado.
// Nada de esto se escribe quemado: la regla sale del catalogo de resultados
// (aprobacion_humana + requiere_admin) y el nivel de autonomia, de parametros.
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const decisiones = useMapGetter('pqrInbox/getDecisiones');
const uiFlags = useMapGetter('pqrInbox/getUIFlags');
const catalogos = useMapGetter('tickets/getCatalogos');
const parametros = useMapGetter('pqrCatalogos/getParametros');
const currentRole = useMapGetter('getCurrentRole');

const cargar = () => store.dispatch('pqrInbox/fetchDecisiones');

onMounted(() => {
  cargar();
  // El catalogo y los parametros alimentan el panel de autoridad y la regla por
  // fila. Lectura permitida a agentes; el catalogo se cachea por sesion.
  store.dispatch('tickets/getCatalogos');
  store.dispatch('pqrCatalogos/fetchParametros');
});

const esAdmin = computed(() => currentRole.value === 'administrator');
const resultados = computed(() => catalogos.value?.resultados || []);

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

// Quien firma un resultado: sale de requiere_admin del catalogo, no de una tabla
// quemada. Es la misma columna que usa la autorizacion del backend (RES-01).
const quienFirma = resultado =>
  resultado?.requiere_admin
    ? t('TICKETS.DECISIONS.RULE_ADMIN')
    : t('TICKETS.DECISIONS.RULE_AGENT');

// La regla concreta que hace esperar la decisión: exige visto bueno humano
// (aprobacion_humana) y ademas quien puede firmarla (requiere_admin).
const reglaAplicada = fila => {
  const resultado = fila.propuesta;
  const partes = [];
  if (!resultado || resultado.aprobacion_humana) {
    partes.push(t('TICKETS.DECISIONS.RULE_HUMAN'));
  }
  partes.push(quienFirma(resultado));
  return partes.join(' · ');
};

// Puede firmar quien sea admin, o cualquier agente si el resultado no exige admin.
// Espeja la doble puerta de RES-01: si no puede, el boton se ve pero deshabilitado.
const puedeFirmar = fila => esAdmin.value || !fila.propuesta?.requiere_admin;

// Nivel de autonomia vigente para resolver, tal como está en parámetros. No se
// edita aquí: se muestra y punto (se cambia en Catálogos y parámetros).
const autonomiaParam = computed(() =>
  (parametros.value || []).find(p => p.clave === 'autonomia_resolver_pqr')
);

const nivelAutonomia = computed(() => {
  // Se mapea el valor del parámetro a su etiqueta con claves literales (el linter
  // no admite claves i18n dinámicas). Si el valor no tiene etiqueta, se muestra
  // crudo tal como está en parámetros, sin inventar nada.
  const valor = autonomiaParam.value?.valor;
  if (valor === 'propone') return t('TICKETS.DECISIONS.AUTONOMY_PROPONE');
  if (valor === 'ejecuta') return t('TICKETS.DECISIONS.AUTONOMY_EJECUTA');
  if (valor === 'ejecuta_con_aviso') {
    return t('TICKETS.DECISIONS.AUTONOMY_EJECUTA_CON_AVISO');
  }
  return valor || t('TICKETS.DECISIONS.AUTONOMY_UNKNOWN');
});

// Sustento derivado del payload real (no un texto inventado): qué propone el
// agente y que no se le ha escrito al cliente.
const sustento = fila =>
  t('TICKETS.DECISIONS.BASIS', {
    result: fila.propuesta?.nombre || '—',
  });

// Ver el sustento abre el expediente en el detalle (DET-01), por nombre de ruta.
// Sin catch: si la navegación falla, que se note (el #42 trae la ruta).
const verSustento = fila => {
  router.push({
    name: 'helic3_pqr_detail',
    params: { accountId: route.params.accountId, id: fila.id },
  });
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

    <div
      v-else
      class="flex flex-col w-full max-w-5xl gap-6 p-6 mx-auto lg:flex-row lg:items-start"
    >
      <!-- Columna: la cola de decisiones -->
      <div class="flex flex-col flex-1 w-full gap-3 min-w-0">
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
              :disabled="!puedeFirmar(fila)"
              @click="pedirAprobacion(fila)"
            />
            <Button
              :label="t('TICKETS.DECISIONS.VIEW')"
              variant="faded"
              color="slate"
              size="sm"
              @click="verSustento(fila)"
            />
            <!-- Negativa/resultado que exige admin: el agente ve el porqué, no un
                 botón que desaparece. Que se note que no puede firmar por su cuenta. -->
            <span
              v-if="!puedeFirmar(fila)"
              class="text-xs font-medium text-n-amber-11"
            >
              {{ t('TICKETS.DECISIONS.CANT_SIGN') }}
            </span>
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
              t('TICKETS.DECISIONS.RULE_APPLIED', { rule: reglaAplicada(fila) })
            }}
          </div>
        </article>
      </div>

      <!-- Columna lateral: quién puede decidir qué + autonomía + aviso -->
      <aside class="flex flex-col w-full gap-4 lg:w-80 shrink-0">
        <section class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <h2 class="mb-1 text-sm font-semibold text-n-slate-12">
            {{ t('TICKETS.DECISIONS.GOVERNANCE_TITLE') }}
          </h2>
          <p class="mb-3 text-xs text-n-slate-11">
            {{ t('TICKETS.DECISIONS.GOVERNANCE_SUBTITLE') }}
          </p>
          <ul class="flex flex-col gap-2.5">
            <li
              v-for="resultado in resultados"
              :key="resultado.id"
              class="flex flex-col gap-0.5"
            >
              <div class="flex items-center gap-2">
                <span class="text-sm text-n-slate-12">{{
                  resultado.nombre
                }}</span>
                <span
                  v-if="resultado.aprobacion_humana"
                  class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-n-amber-3 text-n-amber-11"
                >
                  {{ t('TICKETS.DECISIONS.GOVERNANCE_HUMAN_TAG') }}
                </span>
              </div>
              <span class="text-xs text-n-slate-11">
                {{ quienFirma(resultado) }}
              </span>
            </li>
          </ul>
        </section>

        <section class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <h2 class="mb-1 text-sm font-semibold text-n-slate-12">
            {{ t('TICKETS.DECISIONS.AUTONOMY_TITLE') }}
          </h2>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ nivelAutonomia }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('TICKETS.DECISIONS.AUTONOMY_HINT') }}
          </p>
        </section>

        <section
          class="p-4 text-xs leading-relaxed border rounded-xl border-n-amber-6 bg-n-amber-2 text-n-amber-12"
        >
          {{ t('TICKETS.DECISIONS.NOTICE') }}
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
