<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { useAgentesIaStore } from 'dashboard/store/helic3/agentesIa';
import Button from 'dashboard/components-next/button/Button.vue';
import AgenteCard from './components/AgenteCard.vue';
import ConfirmarBorrado from './components/ConfirmarBorrado.vue';

const router = useRouter();
const { t } = useI18n();
const store = useAgentesIaStore();
const getters = useStoreGetters();
const vuex = useStore();

const query = ref('');
const filtro = ref('all'); // all | active | paused
const aEliminar = ref(null);

const uiFlags = computed(() => store.getUIFlags);
const stats = computed(() => store.getStats);
const inboxes = computed(() => getters['inboxes/getInboxes'].value || []);
const teams = computed(() => getters['teams/getTeams'].value || []);

const teamsById = computed(() =>
  Object.fromEntries(teams.value.map(tm => [tm.id, tm.name]))
);

const agentesFiltrados = computed(() => {
  const q = query.value.trim().toLocaleLowerCase('es');
  return store.getAgentes.filter(a => {
    const estadoOk =
      filtro.value === 'all' ||
      (filtro.value === 'active' ? a.activo : !a.activo);
    const texto = `${a.nombre} ${a.descripcion || ''} ${a.criterio_ruteo || ''}`;
    return estadoOk && texto.toLocaleLowerCase('es').includes(q);
  });
});

// Cobertura: por cada bandeja, qué agente activo la atiende (o el equipo humano).
const cobertura = computed(() =>
  inboxes.value.map(inbox => {
    const agente = store.getAgentes.find(
      a => a.activo && (a.bandejas || []).some(b => b.inbox_id === inbox.id)
    );
    return { id: inbox.id, name: inbox.name, agente: agente?.nombre || null };
  })
);

onMounted(() => {
  store.fetch();
  vuex.dispatch('inboxes/get');
  vuex.dispatch('teams/get');
});

const irACrear = () => router.push({ name: 'agentes_ia_new' });
const irAEditar = id => router.push({ name: 'agentes_ia_edit', params: { agenteId: id } });
const irAEstadoEnVivo = () => router.push({ name: 'agentes_ia_estado_en_vivo' });

const alternar = async agente => {
  try {
    await store.toggle(agente.id);
    useAlert(t(agente.activo ? 'AI_AGENTS.TOGGLE.PAUSED' : 'AI_AGENTS.TOGGLE.ACTIVATED'));
  } catch (error) {
    useAlert(error?.response?.data?.message || t('AI_AGENTS.TOGGLE.ERROR'));
  }
};

const confirmarBorrado = async () => {
  const agente = aEliminar.value;
  aEliminar.value = null;
  try {
    await store.remove(agente.id);
    useAlert(t('AI_AGENTS.DELETE.SUCCESS'));
  } catch (error) {
    useAlert(error?.response?.data?.message || t('AI_AGENTS.DELETE.ERROR'));
  }
};

const limpiarFiltros = () => {
  query.value = '';
  filtro.value = 'all';
};
</script>

<template>
  <div class="flex flex-col gap-5 py-6">
    <!-- Encabezado -->
    <header class="flex items-start justify-between gap-4">
      <div>
        <p class="mb-1 text-xs font-medium tracking-wide uppercase text-n-slate-10">
          {{ t('AI_AGENTS.KICKER') }}
        </p>
        <h1 class="text-2xl font-semibold text-n-slate-12">{{ t('AI_AGENTS.HEADER') }}</h1>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('AI_AGENTS.SUBTITLE') }}</p>
      </div>
      <div class="flex items-center gap-2">
        <Button variant="faded" color="slate" icon="i-lucide-radio" :label="t('AI_AGENTS.LIVE.LINK')" @click="irAEstadoEnVivo" />
        <Button color="teal" :label="t('AI_AGENTS.CREATE')" icon="i-lucide-plus" @click="irACrear" />
      </div>
    </header>

    <!-- Contadores (H3A-13) -->
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <div class="flex items-center gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1">
        <span class="flex items-center justify-center rounded-lg size-9 bg-n-slate-3 text-n-slate-11">
          <span class="i-lucide-bot size-5" />
        </span>
        <div>
          <strong class="block text-xl font-semibold text-n-slate-12">{{ stats.total }}</strong>
          <p class="text-sm text-n-slate-11">{{ t('AI_AGENTS.STATS.TOTAL') }}</p>
        </div>
      </div>
      <div class="flex items-center gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1">
        <span class="flex items-center justify-center rounded-lg size-9 bg-n-teal-3 text-n-teal-11">
          <span class="i-lucide-circle-play size-5" />
        </span>
        <div>
          <strong class="block text-xl font-semibold text-n-slate-12">{{ stats.activos }}</strong>
          <p class="text-sm text-n-slate-11">{{ t('AI_AGENTS.STATS.ACTIVE') }}</p>
        </div>
      </div>
      <div class="flex items-center gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1">
        <span class="flex items-center justify-center rounded-lg size-9 bg-n-slate-3 text-n-slate-11">
          <span class="i-lucide-inbox size-5" />
        </span>
        <div>
          <strong class="block text-xl font-semibold text-n-slate-12">
            {{ stats.bandejasCubiertas }} <span class="text-sm font-normal text-n-slate-10">{{ t('AI_AGENTS.STATS.OF', { total: inboxes.length }) }}</span>
          </strong>
          <p class="text-sm text-n-slate-11">{{ t('AI_AGENTS.STATS.INBOXES') }}</p>
        </div>
      </div>
    </div>

    <!-- Dos columnas: lista + aside (como el mockup) -->
    <div class="grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,1fr),320px]">
      <!-- Lista -->
      <section class="border rounded-xl border-n-weak bg-n-solid-1 h-fit">
        <div class="flex flex-wrap items-center gap-3 p-4 border-b border-n-weak">
          <h2 class="text-sm font-semibold text-n-slate-12">{{ t('AI_AGENTS.LIST.TITLE') }}</h2>
          <div class="flex items-center gap-2 ml-auto">
            <input
              v-model="query"
              type="search"
              class="h-8 px-3 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 w-44"
              :placeholder="t('AI_AGENTS.LIST.SEARCH')"
            />
            <select
              v-model="filtro"
              class="h-8 px-2 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12"
            >
              <option value="all">{{ t('AI_AGENTS.LIST.FILTER_ALL') }}</option>
              <option value="active">{{ t('AI_AGENTS.LIST.FILTER_ACTIVE') }}</option>
              <option value="paused">{{ t('AI_AGENTS.LIST.FILTER_PAUSED') }}</option>
            </select>
          </div>
        </div>

        <div v-if="uiFlags.isFetching" class="p-10 text-sm text-center text-n-slate-10">
          {{ t('AI_AGENTS.LIST.LOADING') }}
        </div>

        <div v-else-if="!agentesFiltrados.length" class="flex flex-col items-center gap-3 p-12 text-center">
          <span class="flex items-center justify-center rounded-full size-12 bg-n-slate-3 text-n-slate-10">
            <span class="i-lucide-bot size-6" />
          </span>
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ store.getAgentes.length ? t('AI_AGENTS.EMPTY.FILTERED_TITLE') : t('AI_AGENTS.EMPTY.TITLE') }}
          </h3>
          <p class="max-w-sm text-sm text-n-slate-11">
            {{ store.getAgentes.length ? t('AI_AGENTS.EMPTY.FILTERED_BODY') : t('AI_AGENTS.EMPTY.BODY') }}
          </p>
          <Button v-if="store.getAgentes.length" variant="faded" color="slate" :label="t('AI_AGENTS.EMPTY.CLEAR')" @click="limpiarFiltros" />
          <Button v-else color="teal" :label="t('AI_AGENTS.CREATE')" icon="i-lucide-plus" @click="irACrear" />
        </div>

        <div v-else class="flex flex-col divide-y divide-n-weak">
          <AgenteCard
            v-for="agente in agentesFiltrados"
            :key="agente.id"
            :agente="agente"
            :team-nombre="agente.team_id ? teamsById[agente.team_id] : null"
            @edit="irAEditar(agente.id)"
            @toggle="alternar(agente)"
            @delete="aEliminar = agente"
          />
        </div>

        <p class="p-4 text-xs border-t border-n-weak text-n-slate-10">{{ t('AI_AGENTS.LIST.FOOTNOTE') }}</p>
      </section>

      <!-- Aside: proceso + cobertura (mockup) -->
      <aside class="flex flex-col gap-5">
        <section class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <h2 class="mb-3 text-sm font-semibold text-n-slate-12">{{ t('AI_AGENTS.PROCESS.TITLE') }}</h2>
          <ol class="flex flex-col gap-3">
            <li class="flex gap-3">
              <span class="flex items-center justify-center rounded-lg size-7 shrink-0 bg-n-slate-3 text-n-slate-11"><span class="i-lucide-inbox size-4" /></span>
              <div><b class="text-sm text-n-slate-12">{{ t('AI_AGENTS.PROCESS.S1_T') }}</b><p class="text-xs text-n-slate-11">{{ t('AI_AGENTS.PROCESS.S1_B') }}</p></div>
            </li>
            <li class="flex gap-3">
              <span class="flex items-center justify-center rounded-lg size-7 shrink-0 bg-n-teal-3 text-n-teal-11"><span class="i-lucide-bot size-4" /></span>
              <div><b class="text-sm text-n-slate-12">{{ t('AI_AGENTS.PROCESS.S2_T') }}</b><p class="text-xs text-n-slate-11">{{ t('AI_AGENTS.PROCESS.S2_B') }}</p></div>
            </li>
            <li class="flex gap-3">
              <span class="flex items-center justify-center rounded-lg size-7 shrink-0 bg-n-slate-3 text-n-slate-11"><span class="i-lucide-users size-4" /></span>
              <div><b class="text-sm text-n-slate-12">{{ t('AI_AGENTS.PROCESS.S3_T') }}</b><p class="text-xs text-n-slate-11">{{ t('AI_AGENTS.PROCESS.S3_B') }}</p></div>
            </li>
          </ol>
        </section>

        <section class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <h2 class="text-sm font-semibold text-n-slate-12">{{ t('AI_AGENTS.COVERAGE.TITLE') }}</h2>
          <p class="mb-3 text-xs text-n-slate-10">{{ t('AI_AGENTS.COVERAGE.HINT') }}</p>
          <div class="flex flex-col gap-3">
            <div v-for="c in cobertura" :key="c.id" class="flex items-center gap-2">
              <span class="rounded-full size-2 shrink-0" :class="c.agente ? 'bg-n-teal-9' : 'bg-n-slate-6'" />
              <div class="min-w-0">
                <b class="block text-sm truncate text-n-slate-12">{{ c.name }}</b>
                <p class="text-xs text-n-slate-11">{{ c.agente || t('AI_AGENTS.COVERAGE.HUMAN') }}</p>
              </div>
            </div>
            <p v-if="!cobertura.length" class="text-xs text-n-slate-10">{{ t('AI_AGENTS.COVERAGE.EMPTY') }}</p>
          </div>
        </section>
      </aside>
    </div>

    <ConfirmarBorrado
      v-if="aEliminar"
      :agente="aEliminar"
      @confirm="confirmarBorrado"
      @cancel="aEliminar = null"
    />
  </div>
</template>
