<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  agente: { type: Object, required: true },
  teamNombre: { type: String, default: null },
});
defineEmits(['edit', 'toggle', 'delete']);

const { t } = useI18n();

const bandejas = computed(() => props.agente.bandejas || []);
const numHerramientas = computed(() => (props.agente.herramientas || []).length);
const proposito = computed(
  () => props.agente.descripcion || props.agente.criterio_ruteo || ''
);
</script>

<template>
  <article class="flex flex-col gap-3 p-5">
    <div class="flex items-start gap-3">
      <span
        class="flex items-center justify-center rounded-lg size-10 shrink-0"
        :class="agente.activo ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-slate-3 text-n-slate-10'"
      >
        <span class="i-lucide-bot size-5" />
      </span>
      <div class="flex-grow min-w-0">
        <div class="flex items-center gap-2">
          <button
            class="text-base font-semibold truncate text-n-slate-12 hover:underline"
            @click="$emit('edit')"
          >
            {{ agente.nombre }}
          </button>
          <span
            v-if="agente.es_sistema"
            class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-slate-3 text-n-slate-11"
          >
            {{ t('AI_AGENTS.CARD.SYSTEM') }}
          </span>
        </div>
        <p class="mt-0.5 text-sm text-n-slate-11 line-clamp-2">{{ proposito }}</p>
      </div>
      <span
        class="px-2 py-0.5 text-xs font-medium rounded-full shrink-0"
        :class="agente.activo ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-slate-3 text-n-slate-10'"
      >
        {{ agente.activo ? t('AI_AGENTS.CARD.ACTIVE') : t('AI_AGENTS.CARD.PAUSED') }}
      </span>
    </div>

    <!-- Bandejas + nº de herramientas (H3A-13) -->
    <div class="flex flex-wrap items-center gap-2">
      <span
        v-for="b in bandejas"
        :key="b.id"
        class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-md bg-n-slate-2 text-n-slate-11 border border-n-weak"
      >
        <span class="i-lucide-inbox size-3" />
        {{ b.inbox_nombre }}
      </span>
      <span
        v-if="!bandejas.length"
        class="px-2 py-0.5 text-xs rounded-md bg-n-slate-2 text-n-slate-10 border border-n-weak"
      >
        {{ t('AI_AGENTS.CARD.NO_INBOXES') }}
      </span>
      <span class="inline-flex items-center gap-1 text-xs text-n-slate-10">
        <span class="i-lucide-wrench size-3" />
        {{ t('AI_AGENTS.CARD.TOOLS_COUNT', { count: numHerramientas }) }}
      </span>
    </div>

    <!-- Pie: deriva a + acciones (como el mockup) -->
    <div class="flex items-center gap-2">
      <span v-if="teamNombre" class="inline-flex items-center gap-1 text-xs text-n-slate-10">
        <span class="i-lucide-users size-3" />
        {{ t('AI_AGENTS.CARD.HANDS_OFF_TO', { team: teamNombre }) }}
      </span>
      <div class="flex items-center gap-2 ml-auto">
        <Button
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-pencil"
          :label="t('AI_AGENTS.CARD.EDIT')"
          @click="$emit('edit')"
        />
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :icon="agente.activo ? 'i-lucide-pause' : 'i-lucide-play'"
          :label="agente.activo ? t('AI_AGENTS.CARD.PAUSE') : t('AI_AGENTS.CARD.ACTIVATE')"
          @click="$emit('toggle')"
        />
        <!-- el agente de sistema (triage) no se puede eliminar (H3A-13) -->
        <Button
          v-if="!agente.es_sistema"
          variant="ghost"
          color="ruby"
          size="sm"
          icon="i-lucide-trash-2"
          :aria-label="t('AI_AGENTS.CARD.DELETE')"
          @click="$emit('delete')"
        />
      </div>
    </div>
  </article>
</template>
