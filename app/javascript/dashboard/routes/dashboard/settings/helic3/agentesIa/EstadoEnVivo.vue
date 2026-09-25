<script setup>
import { onMounted, onBeforeUnmount, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import EstadoEnVivoAPI from 'dashboard/api/helic3/estadoEnVivo';
import Button from 'dashboard/components-next/button/Button.vue';

const router = useRouter();
const { t } = useI18n();

const filas = ref([]);
const cargando = ref(true);
// crit 3: si el canal se cae, degradamos a estado neutro en vez de mostrar datos viejos.
const conectado = ref(true);
let timer = null;

const cargar = async () => {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    conectado.value = false;
    return;
  }
  try {
    const { data } = await EstadoEnVivoAPI.get();
    filas.value = data;
    conectado.value = true;
  } catch (error) {
    conectado.value = false;
  } finally {
    cargando.value = false;
  }
};

const intervenir = async fila => {
  try {
    await EstadoEnVivoAPI.intervenir(fila.conversation_id);
    filas.value = filas.value.filter(f => f.conversation_id !== fila.conversation_id);
    useAlert(t('AI_AGENTS.LIVE.INTERVENED'));
  } catch (error) {
    useAlert(t('AI_AGENTS.LIVE.INTERVENE_ERROR'));
  }
};

const marcarDesconectado = () => {
  conectado.value = false;
};

onMounted(() => {
  cargar();
  timer = setInterval(cargar, 8000);
  window.addEventListener('offline', marcarDesconectado);
  window.addEventListener('online', cargar);
});

onBeforeUnmount(() => {
  if (timer) clearInterval(timer);
  window.removeEventListener('offline', marcarDesconectado);
  window.removeEventListener('online', cargar);
});

const volver = () => router.push({ name: 'agentes_ia_index' });
</script>

<template>
  <div class="flex flex-col gap-6 py-6">
    <button class="flex items-center gap-1 text-sm w-fit text-n-slate-11 hover:text-n-slate-12" @click="volver">
      <span class="i-lucide-chevron-left size-4" /> {{ t('AI_AGENTS.EDITOR.BACK') }}
    </button>

    <header class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold text-n-slate-12">{{ t('AI_AGENTS.LIVE.TITLE') }}</h1>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('AI_AGENTS.LIVE.SUBTITLE') }}</p>
      </div>
      <span
        class="inline-flex items-center gap-2 px-3 py-1 text-xs rounded-full"
        :class="conectado ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-amber-3 text-n-amber-11'"
      >
        <span class="rounded-full size-2" :class="conectado ? 'bg-n-teal-9' : 'bg-n-amber-9'" />
        {{ conectado ? t('AI_AGENTS.LIVE.CONNECTED') : t('AI_AGENTS.LIVE.DISCONNECTED') }}
      </span>
    </header>

    <!-- crit 3: canal caído → estado neutro, no datos viejos -->
    <div v-if="!conectado" class="flex flex-col items-center gap-2 p-12 text-center border rounded-xl border-n-weak bg-n-solid-1">
      <span class="i-lucide-wifi-off size-6 text-n-slate-10" />
      <p class="text-sm text-n-slate-11">{{ t('AI_AGENTS.LIVE.NEUTRAL') }}</p>
    </div>

    <div v-else-if="cargando" class="p-10 text-sm text-center text-n-slate-10">{{ t('AI_AGENTS.LIVE.LOADING') }}</div>

    <div v-else-if="!filas.length" class="flex flex-col items-center gap-2 p-12 text-center border rounded-xl border-n-weak bg-n-solid-1">
      <span class="i-lucide-message-circle-off size-6 text-n-slate-10" />
      <p class="text-sm text-n-slate-11">{{ t('AI_AGENTS.LIVE.EMPTY') }}</p>
    </div>

    <div v-else class="border rounded-xl border-n-weak bg-n-solid-1">
      <div class="flex flex-col divide-y divide-n-weak">
        <div v-for="fila in filas" :key="fila.conversation_id" class="flex items-center gap-3 p-4">
          <span class="flex items-center justify-center rounded-lg size-10 shrink-0 bg-n-teal-3 text-n-teal-11">
            <span class="i-lucide-bot size-5" />
          </span>
          <div class="flex-grow min-w-0">
            <p class="text-sm font-semibold truncate text-n-slate-12">
              {{ fila.contacto || t('AI_AGENTS.LIVE.NO_CONTACT') }}
              <span class="text-n-slate-10">· #{{ fila.conversation_id }}</span>
            </p>
            <p class="text-xs text-n-slate-11">{{ t('AI_AGENTS.LIVE.HANDLED_BY', { agent: fila.agente_nombre }) }}</p>
          </div>
          <Button variant="faded" color="slate" size="sm" icon="i-lucide-hand" :label="t('AI_AGENTS.LIVE.INTERVENE')" @click="intervenir(fila)" />
        </div>
      </div>
    </div>
  </div>
</template>
