<script setup>
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

// IND-01: contenedor de la seccion "Indicadores" -- la barra de pestañas (una
// URL compartible por pestaña, via router children) y el contenido de la
// pestaña activa. Una pestaña aparece SOLO cuando su ticket se integra (hoy,
// solo Garantías); nada de pestañas vacías ni avisos de "próximamente".
const { t } = useI18n();
const route = useRoute();

const TABS = [
  {
    name: 'helic3_indicadores_garantias',
    label: t('HELIC3_INDICADORES.TABS.GARANTIAS'),
  },
];
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <div class="p-6 pb-0 shrink-0">
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('HELIC3_INDICADORES.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ t('HELIC3_INDICADORES.SUBTITLE') }}
      </p>
    </div>
    <div
      class="flex gap-1 p-0.5 m-6 mb-0 rounded-lg bg-n-alpha-1 w-fit shrink-0"
    >
      <router-link
        v-for="tab in TABS"
        :key="tab.name"
        :to="{ name: tab.name }"
        class="px-3 py-1 text-sm font-medium rounded-md"
        :class="
          route.name === tab.name
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
      >
        {{ tab.label }}
      </router-link>
    </div>
    <div class="flex-1 p-6 overflow-auto">
      <router-view />
    </div>
  </div>
</template>
