<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';

// IND-01/IND-02/IND-03/IND-06: contenedor de la seccion "Indicadores" -- la barra de
// pestañas (una URL compartible por pestaña, via router children) y el
// contenido de la pestaña activa. Una pestaña aparece SOLO cuando su ticket
// se integra; nada de pestañas vacías ni avisos de "próximamente". "Todas
// las PQR" no es un ticket aparte: es un resumen que combina lo que ya
// calculan las otras pestañas. "Carga de datos" (IND-03) es la unica que
// ademas se oculta a los agentes (criterio del Dash CX: "un agente no ve la
// pestaña Carga de Datos").
const { t } = useI18n();
const route = useRoute();
const { isAdmin } = useAdmin();

// computed, no un array plano: un array plano evalua t() UNA sola vez al
// montar el componente, antes de que el locale de la cuenta termine de
// resolverse -- la pestaña quedaba en ingles ("Warranties") aunque el resto
// de la pagina ya mostrara espanol, porque nunca se volvia a recalcular.
const TABS = computed(() => {
  const tabs = [
    {
      name: 'helic3_indicadores_garantias',
      label: t('HELIC3_INDICADORES.TABS.GARANTIAS'),
    },
    {
      name: 'helic3_indicadores_pqr',
      label: t('HELIC3_INDICADORES.TABS.PQR'),
    },
    {
      name: 'helic3_indicadores_devoluciones',
      label: t('HELIC3_INDICADORES.TABS.DEVOLUCIONES'),
    },
    {
      name: 'helic3_indicadores_todas',
      label: t('HELIC3_INDICADORES.TABS.TODAS'),
    },
  ];
  if (isAdmin.value) {
    tabs.push({
      name: 'helic3_indicadores_carga',
      label: t('HELIC3_INDICADORES.TABS.CARGA'),
    });
  }
  return tabs;
});
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <!-- Mismo estilo de pestañas con línea inferior del mockup/Dash CX -->
    <nav class="flex gap-4 flex-wrap mx-6 mt-6 border-b border-n-weak shrink-0">
      <router-link
        v-for="tab in TABS"
        :key="tab.name"
        :to="{ name: tab.name }"
        :aria-current="route.name === tab.name ? 'page' : undefined"
        class="px-1 py-3 text-sm border-b-2"
        :class="
          route.name === tab.name
            ? 'border-n-brand text-n-brand font-medium'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
      >
        {{ tab.label }}
      </router-link>
    </nav>
    <div class="flex-1 p-6 overflow-auto">
      <router-view />
    </div>
  </div>
</template>
