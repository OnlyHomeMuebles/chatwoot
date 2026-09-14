<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// VIS-04: badge de procedencia (IA / ERP / Manual) extraído del panel para que el
// panel, la bandeja (VIS-02) y el expediente (VIS-03) lo usen en vez de copiarlo.
// Es una extracción: misma apariencia y misma lógica que tenía en el panel.
const props = defineProps({
  fuente: { type: String, default: '' },
});

const { t } = useI18n();

// el color del badge dice de un vistazo el origen del dato
const claseFuente = computed(() => {
  const classes = {
    ia: 'bg-n-blue-3 text-n-blue-11',
    erp: 'bg-n-amber-3 text-n-amber-11',
    humano: 'bg-n-teal-3 text-n-teal-11',
  };
  return classes[props.fuente] || 'bg-n-alpha-2 text-n-slate-10';
});

// claves i18n literales (el linter no admite claves dinámicas)
const etiqueta = computed(() => {
  if (props.fuente === 'ia') return t('TICKETS.DATA.SOURCE.IA');
  if (props.fuente === 'erp') return t('TICKETS.DATA.SOURCE.ERP');
  if (props.fuente === 'humano') return t('TICKETS.DATA.SOURCE.HUMANO');
  return '';
});
</script>

<template>
  <span
    v-if="fuente"
    class="shrink-0 px-1 py-0.5 rounded text-[10px]"
    :class="claseFuente"
  >
    {{ etiqueta }}
  </span>
</template>
