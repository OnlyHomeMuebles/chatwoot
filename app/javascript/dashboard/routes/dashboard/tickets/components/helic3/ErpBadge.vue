<script setup>
import { useI18n } from 'vue-i18n';

// ERP-11: marca un campo que llenó la consulta a Siesa (misma familia de color ámbar que
// la fuente "ERP" del badge de procedencia). Se quita en cuanto el agente edita el campo.
const { t } = useI18n();
</script>

<template>
  <span
    class="self-start px-1 py-0.5 rounded text-[10px] bg-n-amber-3 text-n-amber-11"
  >
    {{ t('TICKETS.NUEVA.CLIENTE.BADGE_SIESA') }}
  </span>
</template>
