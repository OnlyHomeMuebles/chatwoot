<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  agente: { type: Object, required: true },
});
defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
    @click.self="$emit('cancel')"
  >
    <div class="w-full max-w-md p-6 border shadow-lg rounded-xl border-n-weak bg-n-solid-1">
      <h3 class="text-base font-semibold text-n-slate-12">{{ t('AI_AGENTS.DELETE.TITLE') }}</h3>
      <p class="mt-2 text-sm text-n-slate-11">
        {{ t('AI_AGENTS.DELETE.BODY', { name: props.agente.nombre }) }}
      </p>
      <div class="flex justify-end gap-2 mt-6">
        <Button variant="faded" color="slate" :label="t('AI_AGENTS.DELETE.CANCEL')" @click="$emit('cancel')" />
        <Button color="ruby" :label="t('AI_AGENTS.DELETE.CONFIRM')" @click="$emit('confirm')" />
      </div>
    </div>
  </div>
</template>
