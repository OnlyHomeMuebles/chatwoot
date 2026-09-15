<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// VIS-04: barra del presupuesto de garantía. Un solo componente para las dos
// pantallas (panel de la conversación y expediente): muestra la fracción consumida
// de los días hábiles. La etiqueta "N de X usados" es opcional (hide-label), porque
// el expediente trae su propio texto más detallado y solo reutiliza la barra.
const props = defineProps({
  consumidos: { type: Number, default: 0 },
  total: { type: Number, default: 0 },
  semaforo: { type: String, default: '' },
  hideLabel: { type: Boolean, default: false },
});

const { t } = useI18n();

const pct = computed(() => {
  if (!props.total) return 0;
  return Math.min(100, Math.round((props.consumidos / props.total) * 100));
});

// mismo criterio de color del semáforo que el resto del panel
const barClass = computed(() => {
  const classes = {
    verde: 'bg-n-teal-9',
    amarillo: 'bg-n-amber-9',
    rojo: 'bg-n-ruby-9',
  };
  return classes[props.semaforo] || 'bg-n-slate-9';
});
</script>

<template>
  <div class="flex flex-col gap-1">
    <div class="w-full overflow-hidden rounded-full h-1.5 bg-n-alpha-2">
      <div
        class="h-full rounded-full"
        :class="barClass"
        :style="{ width: `${pct}%` }"
      />
    </div>
    <span v-if="!hideLabel" class="text-xs text-n-slate-11">
      {{ t('TICKETS.WARRANTY.BUDGET', { used: consumidos, total }) }}
    </span>
  </div>
</template>
