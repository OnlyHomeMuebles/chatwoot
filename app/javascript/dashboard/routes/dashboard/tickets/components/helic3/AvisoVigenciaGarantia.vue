<script setup>
// GAR-09: aviso de vigencia de garantía en "Datos del caso". Recibe
// expediente.vigencia_garantia (lo calcula el backend) y solo lo pinta. Si llega
// null (expediente que no es de garantía o sin el parámetro), no pinta nada.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  vigencia: { type: Object, default: null },
});

const { t } = useI18n();

const P = 'TICKETS.DATA.VIGENCIA';

// Color (tokens n- del tema, para modo oscuro) y título por estado. Dentro/fuera
// van cortos (solo el título, pedido de Karen); las fechas se ven en las líneas
// bajo "Fecha de compra". Solo "sin fecha" lleva un texto de ayuda.
const ESTILOS = {
  dentro: {
    clases: 'bg-n-teal-3 border-n-teal-4 text-n-teal-11',
    titleKey: `${P}.DENTRO_TITLE`,
  },
  fuera: {
    clases: 'bg-n-ruby-3 border-n-ruby-4 text-n-ruby-11',
    titleKey: `${P}.FUERA_TITLE`,
  },
  sin_fecha_compra: {
    clases: 'bg-n-amber-3 border-n-amber-4 text-n-amber-11',
    titleKey: `${P}.SIN_FECHA_TITLE`,
    textKey: `${P}.SIN_FECHA_TEXT`,
  },
};

const estilo = computed(() => ESTILOS[props.vigencia?.estado] || null);
</script>

<template>
  <div
    v-if="estilo"
    data-testid="aviso-vigencia"
    class="p-3 mb-3 text-sm border rounded-lg"
    :class="estilo.clases"
  >
    <p class="font-medium">{{ t(estilo.titleKey) }}</p>
    <p v-if="estilo.textKey" class="mt-0.5">{{ t(estilo.textKey) }}</p>
  </div>
</template>
