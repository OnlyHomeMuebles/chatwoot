<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

// Wrapper propio del modulo (H3A-13): a lo ancho, sin el cap de Ajustes, para que
// la vista llene el espacio como en el mockup.
const route = useRoute();
const routeKey = computed(() => route.fullPath);
</script>

<template>
  <div class="flex flex-col w-full h-full px-8 pt-4 pb-10 overflow-auto bg-n-surface-1">
    <div class="w-full mx-auto max-w-[1200px]">
      <router-view v-slot="{ Component }">
        <component :is="Component" :key="routeKey" />
      </router-view>
    </div>
  </div>
</template>
