<script setup>
import { useI18n } from 'vue-i18n';

// ERP-05: aviso gemelo del badge "Siesa" pero en gris: la consulta encontro al cliente y
// este campo no vino (Siesa/Terceros no lo trae). Senala ausencia, no dato; por eso el tono
// neutro en vez del ambar de ErpBadge.
const { t } = useI18n();
</script>

<template>
  <span
    class="self-start px-1 py-0.5 rounded text-[10px] bg-n-slate-3 text-n-slate-11"
  >
    {{ t('TICKETS.NUEVA.CLIENTE.BADGE_SIN_DATO') }}
  </span>
</template>
