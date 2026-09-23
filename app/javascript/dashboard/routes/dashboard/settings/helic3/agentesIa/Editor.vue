<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAgentesIaStore } from 'dashboard/store/helic3/agentesIa';
import Button from 'dashboard/components-next/button/Button.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const getters = useStoreGetters();
const vuex = useStore();
const store = useAgentesIaStore();

const TABS = ['IDENTITY', 'INBOXES', 'RESPONSE', 'POLICIES'];
const tab = ref(0);
const error = ref('');
const errorField = ref('');
const guardando = ref(false);

const agenteId = computed(() => route.params.agenteId);
const esEdicion = computed(() => !!agenteId.value);

const inboxes = computed(() => getters['inboxes/getInboxes'].value || []);
const teams = computed(() => getters['teams/getTeams'].value || []);
const catalogo = computed(() => store.getCatalogo);

const inboxNombre = id => inboxes.value.find(i => i.id === id)?.name || `#${id}`;
const teamNombre = computed(
  () => teams.value.find(tm => tm.id === draft.team_id)?.name || t('AI_AGENTS.EDITOR.FIELDS.TEAM_NONE')
);

const draft = reactive({
  nombre: '',
  criterio_ruteo: '',
  prompt: '',
  tono: '',
  horario: 'siempre',
  activo: false,
  inbox_ids: [],
  herramientas: [],
  confianza_minima: 85,
  max_respuestas: 8,
  team_id: null,
  mensaje_handoff: '',
});
let baseline = '';

const dirty = computed(() => JSON.stringify(draft) !== baseline);

const cargarDesde = agente => {
  Object.assign(draft, {
    nombre: agente.nombre || '',
    criterio_ruteo: agente.criterio_ruteo || '',
    prompt: agente.prompt || '',
    tono: agente.tono || '',
    horario: agente.horario || 'siempre',
    activo: !!agente.activo,
    inbox_ids: (agente.bandejas || []).map(b => b.inbox_id),
    herramientas: [...(agente.herramientas || [])],
    confianza_minima: agente.confianza_minima ?? 85,
    max_respuestas: agente.max_respuestas ?? 8,
    team_id: agente.team_id ?? null,
    mensaje_handoff: agente.mensaje_handoff || '',
  });
  baseline = JSON.stringify(draft);
};

onMounted(async () => {
  vuex.dispatch('inboxes/get');
  vuex.dispatch('teams/get');
  if (!store.getCatalogo.herramientas.length) store.fetchCatalogo();
  if (esEdicion.value) {
    if (!store.getAgentes.length) await store.fetch();
    const agente = store.getAgente(agenteId.value);
    if (agente) cargarDesde(agente);
  } else {
    baseline = JSON.stringify(draft);
  }
});

const toggleInbox = id => {
  const i = draft.inbox_ids.indexOf(id);
  if (i === -1) draft.inbox_ids.push(id);
  else draft.inbox_ids.splice(i, 1);
};
const toggleHerramienta = clave => {
  const i = draft.herramientas.indexOf(clave);
  if (i === -1) draft.herramientas.push(clave);
  else draft.herramientas.splice(i, 1);
};

// codigo interno: se autogenera del nombre en la creación (inmutable tras crear).
const generarCodigo = () =>
  `agente_${draft.nombre
    .toLocaleLowerCase('es')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40) || Date.now().toString(36)}`;

const validar = () => {
  if (!draft.nombre.trim()) return [0, t('AI_AGENTS.EDITOR.ERRORS.NAME'), 'ai-nombre'];
  if (!draft.criterio_ruteo.trim()) return [0, t('AI_AGENTS.EDITOR.ERRORS.PURPOSE'), 'ai-purpose'];
  if (draft.activo && !draft.inbox_ids.length)
    return [1, t('AI_AGENTS.EDITOR.ERRORS.INBOXES'), ''];
  if (!draft.prompt.trim()) return [2, t('AI_AGENTS.EDITOR.ERRORS.PROMPT'), 'ai-prompt'];
  const c = Number(draft.confianza_minima);
  if (draft.confianza_minima !== null && (c < 50 || c > 100))
    return [3, t('AI_AGENTS.EDITOR.ERRORS.CONFIDENCE'), 'ai-confidence'];
  const m = Number(draft.max_respuestas);
  if (draft.max_respuestas !== null && (m < 1 || m > 30))
    return [3, t('AI_AGENTS.EDITOR.ERRORS.MAX'), 'ai-max'];
  if (!draft.mensaje_handoff.trim())
    return [3, t('AI_AGENTS.EDITOR.ERRORS.HANDOFF'), 'ai-handoff'];
  return null;
};

const foco = id => {
  const el = document.getElementById(id);
  if (el) el.focus();
};

const guardar = async () => {
  const fallo = validar();
  if (fallo) {
    tab.value = fallo[0];
    error.value = fallo[1];
    errorField.value = fallo[2];
    if (fallo[2]) setTimeout(() => foco(fallo[2]), 0);
    return;
  }
  error.value = '';
  guardando.value = true;
  const payload = {
    nombre: draft.nombre.trim(),
    criterio_ruteo: draft.criterio_ruteo.trim(),
    descripcion: draft.criterio_ruteo.trim(),
    prompt: draft.prompt.trim(),
    tono: draft.tono,
    horario: draft.horario,
    activo: draft.activo,
    inbox_ids: draft.inbox_ids,
    herramientas: draft.herramientas,
    confianza_minima: draft.confianza_minima === '' ? null : draft.confianza_minima,
    max_respuestas: draft.max_respuestas === '' ? null : draft.max_respuestas,
    team_id: draft.team_id || null,
    mensaje_handoff: draft.mensaje_handoff.trim(),
  };
  try {
    if (esEdicion.value) {
      await store.update(Number(agenteId.value), payload);
      useAlert(t('AI_AGENTS.EDITOR.SAVED'));
    } else {
      await store.create({ ...payload, codigo: generarCodigo() });
      useAlert(t('AI_AGENTS.EDITOR.CREATED'));
    }
    baseline = JSON.stringify(draft);
    router.push({ name: 'agentes_ia_index' });
  } catch (e) {
    useAlert(e?.response?.data?.message || t('AI_AGENTS.EDITOR.ERROR'));
  } finally {
    guardando.value = false;
  }
};

const salir = () => router.push({ name: 'agentes_ia_index' });

// aviso de cambios sin guardar (H3A-14 crit 2)
onBeforeRouteLeave(() => {
  if (dirty.value && !window.confirm(t('AI_AGENTS.EDITOR.DISCARD_CONFIRM'))) return false;
  return true;
});
const alSalirVentana = e => {
  if (dirty.value) {
    e.preventDefault();
    e.returnValue = '';
  }
};
onMounted(() => window.addEventListener('beforeunload', alSalirVentana));
onBeforeUnmount(() => window.removeEventListener('beforeunload', alSalirVentana));

const irTab = i => {
  tab.value = i;
};
</script>

<template>
  <div class="flex flex-col gap-6 py-6">
    <button class="flex items-center gap-1 text-sm w-fit text-n-slate-11 hover:text-n-slate-12" @click="salir">
      <span class="i-lucide-chevron-left size-4" /> {{ t('AI_AGENTS.EDITOR.BACK') }}
    </button>
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ esEdicion ? t('AI_AGENTS.EDITOR.EDIT_TITLE') : t('AI_AGENTS.EDITOR.NEW_TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('AI_AGENTS.EDITOR.SUBTITLE') }}</p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-xs" :class="dirty ? 'text-n-amber-11' : 'text-n-slate-10'">
          {{ dirty ? t('AI_AGENTS.EDITOR.UNSAVED') : t('AI_AGENTS.EDITOR.NO_CHANGES') }}
        </span>
        <Button variant="faded" color="slate" :label="t('AI_AGENTS.EDITOR.CANCEL')" @click="salir" />
        <Button
          color="teal"
          :is-loading="guardando"
          :label="esEdicion ? t('AI_AGENTS.EDITOR.SAVE') : t('AI_AGENTS.CREATE')"
          icon="i-lucide-check"
          @click="guardar"
        />
      </div>
    </header>

    <!-- Pestañas -->
    <div class="flex flex-wrap gap-1.5 p-1.5 rounded-xl bg-n-alpha-black1 w-fit">
      <button
        v-for="(tk, i) in TABS"
        :key="tk"
        class="px-4 py-2 text-sm rounded-lg"
        :class="tab === i ? 'bg-n-solid-1 text-n-slate-12 shadow-sm font-medium' : 'text-n-slate-11 hover:text-n-slate-12'"
        @click="irTab(i)"
      >
        <span class="mr-1.5 text-n-slate-10">0{{ i + 1 }}</span>{{ t(`AI_AGENTS.EDITOR.TABS.${tk}`) }}
      </button>
    </div>

    <div v-if="error" class="p-3 text-sm border rounded-lg border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11">
      {{ error }}
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr),360px]">
      <form class="p-6 border rounded-xl border-n-weak bg-n-solid-1" @submit.prevent="guardar">
        <!-- 01 Identidad -->
        <div v-show="tab === 0" class="flex flex-col gap-4">
          <div>
            <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-nombre">
              {{ t('AI_AGENTS.EDITOR.FIELDS.NAME') }} <span class="text-n-ruby-9">*</span>
            </label>
            <input id="ai-nombre" v-model="draft.nombre" maxlength="70" class="w-full h-11 px-3.5 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12" :placeholder="t('AI_AGENTS.EDITOR.FIELDS.NAME_PH')" />
          </div>
          <div>
            <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-purpose">
              {{ t('AI_AGENTS.EDITOR.FIELDS.PURPOSE') }} <span class="text-n-ruby-9">*</span>
            </label>
            <textarea id="ai-purpose" v-model="draft.criterio_ruteo" rows="3" maxlength="500" class="w-full px-3.5 py-2.5 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12" :placeholder="t('AI_AGENTS.EDITOR.FIELDS.PURPOSE_PH')" />
            <p class="mt-1 text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.FIELDS.PURPOSE_HINT') }}</p>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <label class="flex gap-2 p-3 border rounded-lg cursor-pointer border-n-weak" :class="!draft.activo ? 'ring-1 ring-n-brand' : ''">
              <input v-model="draft.activo" type="radio" :value="false" />
              <span><b class="text-sm text-n-slate-12">{{ t('AI_AGENTS.CARD.PAUSED') }}</b><p class="text-xs text-n-slate-11">{{ t('AI_AGENTS.EDITOR.FIELDS.PAUSED_HINT') }}</p></span>
            </label>
            <label class="flex gap-2 p-3 border rounded-lg cursor-pointer border-n-weak" :class="draft.activo ? 'ring-1 ring-n-brand' : ''">
              <input v-model="draft.activo" type="radio" :value="true" />
              <span><b class="text-sm text-n-slate-12">{{ t('AI_AGENTS.CARD.ACTIVE') }}</b><p class="text-xs text-n-slate-11">{{ t('AI_AGENTS.EDITOR.FIELDS.ACTIVE_HINT') }}</p></span>
            </label>
          </div>
        </div>

        <!-- 02 Bandejas -->
        <div v-show="tab === 1" class="flex flex-col gap-4">
          <p class="text-sm text-n-slate-11">{{ t('AI_AGENTS.EDITOR.FIELDS.INBOXES_INTRO') }}</p>
          <div class="flex flex-col gap-2">
            <label v-for="inbox in inboxes" :key="inbox.id" class="flex items-center gap-3 p-3 border rounded-lg cursor-pointer border-n-weak">
              <input type="checkbox" :checked="draft.inbox_ids.includes(inbox.id)" @change="toggleInbox(inbox.id)" />
              <span class="text-sm text-n-slate-12">{{ inbox.name }}</span>
            </label>
            <p v-if="!inboxes.length" class="text-sm text-n-slate-10">{{ t('AI_AGENTS.EDITOR.FIELDS.NO_INBOXES') }}</p>
          </div>
          <div>
            <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-schedule">{{ t('AI_AGENTS.EDITOR.FIELDS.SCHEDULE') }}</label>
            <select id="ai-schedule" v-model="draft.horario" class="h-11 px-3 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12">
              <option value="siempre">{{ t('AI_AGENTS.EDITOR.FIELDS.SCHEDULE_ALWAYS') }}</option>
              <option value="horario_atencion">{{ t('AI_AGENTS.EDITOR.FIELDS.SCHEDULE_HOURS') }}</option>
            </select>
          </div>
        </div>

        <!-- 03 Respuesta -->
        <div v-show="tab === 2" class="flex flex-col gap-4">
          <div>
            <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-tono">{{ t('AI_AGENTS.EDITOR.FIELDS.TONE') }}</label>
            <input id="ai-tono" v-model="draft.tono" maxlength="60" class="w-full h-11 px-3.5 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12" :placeholder="t('AI_AGENTS.EDITOR.FIELDS.TONE_PH')" />
          </div>
          <div>
            <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-prompt">{{ t('AI_AGENTS.EDITOR.FIELDS.PROMPT') }} <span class="text-n-ruby-9">*</span></label>
            <textarea id="ai-prompt" v-model="draft.prompt" rows="8" maxlength="6000" class="w-full px-3.5 py-2.5 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12" />
            <p class="mt-1 text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.FIELDS.PROMPT_HINT') }}</p>
          </div>
        </div>

        <!-- 04 Capacidades y políticas -->
        <div v-show="tab === 3" class="flex flex-col gap-4">
          <!-- Capacidades: herramientas del catálogo (H3A-03) -->
          <div>
            <p class="mb-2 text-sm font-medium text-n-slate-12">{{ t('AI_AGENTS.EDITOR.FIELDS.TOOLS') }}</p>
            <div class="flex flex-col gap-2">
              <label v-for="h in catalogo.herramientas" :key="h.clave" class="flex items-start gap-3 p-3 border rounded-lg cursor-pointer border-n-weak">
                <input type="checkbox" :checked="draft.herramientas.includes(h.clave)" @change="toggleHerramienta(h.clave)" />
                <span><b class="text-sm text-n-slate-12">{{ h.etiqueta }}</b><p class="text-xs text-n-slate-11">{{ h.ayuda }}</p></span>
              </label>
            </div>
          </div>
          <!-- Reglas duras: solo lectura, texto del catálogo (H3A-14 crit 4) -->
          <div v-if="catalogo.reglas_duras">
            <p class="mb-1 text-sm font-medium text-n-slate-12">{{ t('AI_AGENTS.EDITOR.FIELDS.HARD_RULES') }}</p>
            <p class="mb-2 text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.FIELDS.HARD_RULES_HINT') }}</p>
            <pre class="p-3 overflow-auto text-xs whitespace-pre-wrap border rounded-lg border-n-weak bg-n-slate-2 text-n-slate-11 max-h-48">{{ catalogo.reglas_duras }}</pre>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-confidence">{{ t('AI_AGENTS.EDITOR.FIELDS.CONFIDENCE') }}</label>
              <input id="ai-confidence" v-model.number="draft.confianza_minima" type="number" min="50" max="100" class="w-full h-11 px-3.5 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12" />
            </div>
            <div>
              <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-max">{{ t('AI_AGENTS.EDITOR.FIELDS.MAX') }}</label>
              <input id="ai-max" v-model.number="draft.max_respuestas" type="number" min="1" max="30" class="w-full h-11 px-3.5 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12" />
            </div>
          </div>
          <div>
            <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-team">{{ t('AI_AGENTS.EDITOR.FIELDS.TEAM') }}</label>
            <select id="ai-team" v-model="draft.team_id" class="h-11 px-3 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12">
              <option :value="null">{{ t('AI_AGENTS.EDITOR.FIELDS.TEAM_NONE') }}</option>
              <option v-for="team in teams" :key="team.id" :value="team.id">{{ team.name }}</option>
            </select>
          </div>
          <div>
            <label class="block mb-1 text-sm font-medium text-n-slate-12" for="ai-handoff">{{ t('AI_AGENTS.EDITOR.FIELDS.HANDOFF') }} <span class="text-n-ruby-9">*</span></label>
            <textarea id="ai-handoff" v-model="draft.mensaje_handoff" rows="2" maxlength="1500" class="w-full px-3.5 py-2.5 text-[15px] border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12" />
          </div>
        </div>

        <!-- Navegación de pasos -->
        <div class="flex items-center justify-between pt-5 mt-5 border-t border-n-weak">
          <span class="text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.STEP', { n: tab + 1, total: TABS.length }) }}</span>
          <div class="flex gap-2">
            <Button v-if="tab > 0" variant="faded" color="slate" :label="t('AI_AGENTS.EDITOR.PREV')" @click="irTab(tab - 1)" />
            <Button v-if="tab < TABS.length - 1" color="teal" trailing-icon icon="i-lucide-arrow-right" :label="t('AI_AGENTS.EDITOR.NEXT')" @click="irTab(tab + 1)" />
            <Button v-else color="teal" :is-loading="guardando" icon="i-lucide-check" :label="esEdicion ? t('AI_AGENTS.EDITOR.SAVE') : t('AI_AGENTS.CREATE')" @click="guardar" />
          </div>
        </div>
      </form>

      <!-- Resumen lateral (como el mockup) -->
      <aside class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1 h-fit">
        <div class="flex items-start gap-3">
          <span class="flex items-center justify-center rounded-lg size-9 shrink-0 bg-n-teal-3 text-n-teal-11"><span class="i-lucide-bot size-5" /></span>
          <div class="min-w-0">
            <p class="text-xs tracking-wide uppercase text-n-slate-10">{{ t('AI_AGENTS.EDITOR.SUMMARY.KICKER') }}</p>
            <b class="block text-base text-n-slate-12 truncate">{{ draft.nombre || t('AI_AGENTS.EDITOR.SUMMARY.PLACEHOLDER') }}</b>
          </div>
        </div>
        <p class="text-sm text-n-slate-11 line-clamp-3">{{ draft.criterio_ruteo || t('AI_AGENTS.EDITOR.SUMMARY.PURPOSE_PH') }}</p>
        <span
          class="px-2 py-0.5 text-xs font-medium rounded-full w-fit"
          :class="draft.activo ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-slate-3 text-n-slate-10'"
        >{{ draft.activo ? t('AI_AGENTS.CARD.ACTIVE') : t('AI_AGENTS.CARD.PAUSED') }}</span>
        <div class="h-px bg-n-weak" />
        <dl class="flex flex-col gap-4 text-sm">
          <div>
            <dt class="mb-1 text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.SUMMARY.INBOXES') }}</dt>
            <dd class="flex flex-wrap gap-1">
              <span v-for="id in draft.inbox_ids" :key="id" class="px-2 py-0.5 text-xs rounded-md bg-n-slate-2 border border-n-weak text-n-slate-11">{{ inboxNombre(id) }}</span>
              <span v-if="!draft.inbox_ids.length" class="text-n-slate-11">{{ t('AI_AGENTS.EDITOR.SUMMARY.NO_INBOXES') }}</span>
            </dd>
          </div>
          <div>
            <dt class="mb-1 text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.SUMMARY.TONE') }}</dt>
            <dd class="text-n-slate-12">{{ draft.tono || '—' }} · {{ draft.horario === 'horario_atencion' ? t('AI_AGENTS.EDITOR.FIELDS.SCHEDULE_HOURS') : t('AI_AGENTS.EDITOR.FIELDS.SCHEDULE_ALWAYS') }}</dd>
          </div>
          <div>
            <dt class="mb-1 text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.SUMMARY.TOOLS') }}</dt>
            <dd class="text-n-slate-12">{{ t('AI_AGENTS.EDITOR.SUMMARY.TOOLS_LIMITS', { tools: draft.herramientas.length, max: draft.max_respuestas || '—' }) }}</dd>
          </div>
          <div>
            <dt class="mb-1 text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.SUMMARY.HANDOFF') }}</dt>
            <dd class="text-n-slate-12">{{ teamNombre }}</dd>
            <dd class="text-xs text-n-slate-10">{{ t('AI_AGENTS.EDITOR.SUMMARY.HANDOFF_HINT', { c: draft.confianza_minima || '—' }) }}</dd>
          </div>
        </dl>
        <div class="h-px bg-n-weak" />
        <p class="flex gap-2 text-xs text-n-slate-10">
          <span class="i-lucide-shield size-4 shrink-0" />{{ t('AI_AGENTS.EDITOR.SUMMARY.NOTE') }}
        </p>
      </aside>
    </div>
  </div>
</template>
