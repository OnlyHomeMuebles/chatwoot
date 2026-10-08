# FMT-03 · Pestaña «Formatos» — Plan de implementación (MVP)

> **Para workers:** SUB-SKILL REQUERIDA: superpowers:executing-plans (o
> subagent-driven-development) para implementar tarea por tarea. Pasos con checkbox.

**Goal:** Una pestaña «Formatos» dentro de Catálogos donde un admin sube un `.docx`, ve su PDF (datos de ejemplo) y lo activa; el agente lo ve en solo lectura.

**Architecture:** Pestaña interna de `PqrCatalogosPage.vue` que monta `FormatosPanel.vue`; el panel usa un store Vuex (`helic3Formatos`) que llama a un cliente `api/helic3/formatos.js` contra la API de FMT-02. Las tarjetas (`FormatoCard.vue`) son de presentación: emiten eventos, el panel habla con el store.

**Tech Stack:** Vue 3 (`<script setup>`), Vuex, components-next (Button/Dialog/Input/Spinner), Vitest + @vue/test-utils, i18n (vue-i18n). Dev server Vite en Docker.

**Spec:** [docs/helic3/fmt-03-pantalla-diseno.md](fmt-03-pantalla-diseno.md)

## Global Constraints

- **Frontera:** sin paquetes npm nuevos; NO tocar `settings.routes.js`, `tickets.routes.js`, `Sidebar.vue`, `package.json`, `pnpm-lock.yaml`. Modificar `store/index.js` y `mutation-types.js` SÍ está permitido (es el patrón con que se registró `pqrCatalogos`). Todo lo nuevo bajo rutas Helic3.
- **Patrones a copiar:** API `api/pqrCatalogos.js`; store `store/modules/pqrCatalogos.js`; subida multipart `PqrDetailPage.vue` + `api/tickets.js#subirDocumento`; permisos `esAdmin` (getter `getCurrentRole`); spec `pages/specs/PqrDetailPage.spec.js` (mockea `dashboard/composables/store`, `vue-i18n`, usa `data-testid`).
- **Convención de test frontend del proyecto:** solo hay specs a nivel de componente (no de store). Por eso Task 1 (infra) se verifica con `pnpm eslint`, y los specs Vitest viven en los componentes (Tasks 2-3).
- **Guardián OSS** antes de cada commit: `PYTHONUTF8=1 python .claude/skills/revisar-oss/guard.py --staged`. Hook pre-commit roto en este entorno → commitear con `--no-verify` tras correr eslint. Cerrar commits con `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Vite gotcha (Windows/Docker):** el dev server no detecta cambios; para ver la UI, `docker compose restart vite`.

## Review Focus

Entradas que el spec implica y que conviene cubrir:
1. **Formato sin versión activa** → la tarjeta dice «aún no tiene plantilla» y no ofrece descargar/activar nada roto (Task 2).
2. **Respuesta 422 al subir** (marcador desconocido) → la tarjeta muestra cada desconocido + sugerencia y NO cambia la activa (Task 2).
3. **Agente (no admin)** → no ve subir/activar/descartar, pero sí las tarjetas y la vista previa (Task 2).
4. **Fallo al cargar la vista previa** (blob/red) → aviso y opción «abrir en pestaña nueva», sin romper el panel (Task 3).
5. **«Copiar» marcador** → escribe `{{NOMBRE}}` en el portapapeles aunque `navigator.clipboard` sea asíncrono (Task 3).

---

### Task 1: Cliente de API + store + i18n (infraestructura)

**Files:**
- Create: `app/javascript/dashboard/api/helic3/formatos.js`
- Create: `app/javascript/dashboard/store/modules/helic3Formatos.js`
- Modify: `app/javascript/dashboard/store/index.js` (import + registrar módulo)
- Modify: `app/javascript/dashboard/store/mutation-types.js` (constantes)
- Modify: `app/javascript/dashboard/i18n/locale/es/tickets.json` y `en/tickets.json` (sección `TICKETS.FORMATOS`)

**Interfaces:**
- Produces: `helic3FormatosAPI` con `listFormatos()`, `marcadores()`, `subirPlantilla(formatoId, formData)`, `vistaPrevia(plantillaId, formato='pdf')`, `descargarOriginal(plantillaId)`, `activar(plantillaId)`, `descartar(plantillaId)`; store module `helic3Formatos` con getters `getFormatos`/`getMarcadores`/`getUIFlags` y actions `fetchFormatos`/`fetchMarcadores`/`subirPlantilla`/`activar`/`descartar`.

- [ ] **Step 1: Cliente de API**

`app/javascript/dashboard/api/helic3/formatos.js`:
```js
/* global axios */
import ApiClient from '../ApiClient';

class Helic3FormatosAPI extends ApiClient {
  constructor() {
    super('helic3/admin', { accountScoped: true });
  }

  listFormatos() {
    return axios.get(`${this.url}/formatos`);
  }

  marcadores() {
    return axios.get(`${this.url}/formatos/marcadores`);
  }

  subirPlantilla(formatoId, formData) {
    return axios.post(`${this.url}/formatos/${formatoId}/plantillas`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  vistaPrevia(plantillaId, formato = 'pdf') {
    return axios.get(`${this.url}/plantillas/${plantillaId}/vista_previa`, {
      params: { formato },
      responseType: 'blob',
    });
  }

  descargarOriginal(plantillaId) {
    return axios.get(`${this.url}/plantillas/${plantillaId}/original`, {
      responseType: 'blob',
    });
  }

  activar(plantillaId) {
    return axios.post(`${this.url}/plantillas/${plantillaId}/activar`);
  }

  descartar(plantillaId) {
    return axios.delete(`${this.url}/plantillas/${plantillaId}`);
  }
}

export default new Helic3FormatosAPI();
```
> Verifica contra `api/pqrCatalogos.js` que `axios` es global y el import de `ApiClient` es correcto (ruta relativa desde `api/helic3/` es `../ApiClient`).

- [ ] **Step 2: Constantes de mutación**

En `store/mutation-types.js`, agregar (junto a las de `PQR`):
```js
  SET_HELIC3_FORMATOS: 'SET_HELIC3_FORMATOS',
  SET_HELIC3_MARCADORES: 'SET_HELIC3_MARCADORES',
  SET_HELIC3_FORMATOS_UI_FLAG: 'SET_HELIC3_FORMATOS_UI_FLAG',
```
(Respeta el formato exacto del archivo: puede ser un objeto `export default { ... }`.)

- [ ] **Step 3: Store module**

`app/javascript/dashboard/store/modules/helic3Formatos.js`:
```js
import types from '../mutation-types';
import Helic3FormatosAPI from '../../api/helic3/formatos';

export const state = {
  formatos: [],
  marcadores: {},
  uiFlags: { isFetching: false, isSaving: false },
};

export const getters = {
  getFormatos: $state => $state.formatos,
  getMarcadores: $state => $state.marcadores,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  fetchFormatos: async ({ commit }) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await Helic3FormatosAPI.listFormatos();
      commit(types.SET_HELIC3_FORMATOS, data);
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isFetching: false });
    }
  },
  fetchMarcadores: async ({ commit }) => {
    const { data } = await Helic3FormatosAPI.marcadores();
    commit(types.SET_HELIC3_MARCADORES, data);
  },
  subirPlantilla: async ({ commit, dispatch }, { formatoId, formData }) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      const { data } = await Helic3FormatosAPI.subirPlantilla(formatoId, formData);
      await dispatch('fetchFormatos');
      return data;
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  activar: async ({ commit, dispatch }, plantillaId) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      await Helic3FormatosAPI.activar(plantillaId);
      await dispatch('fetchFormatos');
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  descartar: async ({ commit, dispatch }, plantillaId) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      await Helic3FormatosAPI.descartar(plantillaId);
      await dispatch('fetchFormatos');
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  // devuelven el blob (el componente arma la URL); el panel NO llama la API directo.
  vistaPrevia: (_ctx, plantillaId) =>
    Helic3FormatosAPI.vistaPrevia(plantillaId).then(respuesta => respuesta.data),
  descargarOriginal: (_ctx, plantillaId) =>
    Helic3FormatosAPI.descargarOriginal(plantillaId).then(respuesta => respuesta.data),
};

export const mutations = {
  [types.SET_HELIC3_FORMATOS]: ($state, data) => { $state.formatos = data; },
  [types.SET_HELIC3_MARCADORES]: ($state, data) => { $state.marcadores = data; },
  [types.SET_HELIC3_FORMATOS_UI_FLAG]: ($state, flag) => {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
```
> `subirPlantilla` NO atrapa el error: lo relanza para que el panel lea el 422.

- [ ] **Step 4: Registrar el módulo**

En `store/index.js`: `import helic3Formatos from './modules/helic3Formatos';` y añadir `helic3Formatos,` dentro de `modules: { ... }` (al lado de `pqrCatalogos`).

- [ ] **Step 5: i18n**

En `i18n/locale/es/tickets.json`, dentro de `"TICKETS"`, agregar:
```json
"FORMATOS": {
  "TITLE": "Formatos",
  "SIN_PLANTILLA": "Aún no tiene plantilla; no se puede generar.",
  "VERSION_ACTIVA": "Versión %{version} · activada el %{fecha} por %{quien}",
  "SUBIR": "Subir nueva versión",
  "DESCARGAR": "Descargar .docx",
  "ACTIVAR": "Activar esta versión",
  "ACTIVAR_CONFIRMACION": "Desde ahora todos los casos usan esta versión del formato. ¿Activar?",
  "DESCARTAR": "Descartar borrador",
  "VISTA_PREVIA": "Vista previa",
  "ABRIR_NUEVA_PESTANA": "Abrir en pestaña nueva",
  "DESCONOCIDOS": "Marcadores no reconocidos:",
  "MARCADORES": { "TITLE": "Marcadores disponibles", "COPIAR": "Copiar", "COPIADO": "Copiado" },
  "SOLO_LECTURA": "Solo lectura",
  "GUARDADO": "Listo",
  "FORBIDDEN": "No tienes permiso para esta acción.",
  "ERROR": "Ocurrió un error. Inténtalo de nuevo."
}
```
En `en/tickets.json`, la misma estructura con los textos en inglés.

- [ ] **Step 6: eslint**

Run: `docker compose exec vite pnpm eslint app/javascript/dashboard/api/helic3/ app/javascript/dashboard/store/modules/helic3Formatos.js`
Expected: sin errores. (Si `vite` no es el servicio correcto, usar el contenedor donde corre pnpm.)

- [ ] **Step 7: Guardián + commit**

```
PYTHONUTF8=1 python .claude/skills/revisar-oss/guard.py --staged   # tras git add
git add -A && git commit --no-verify -m "feat(formatos): cliente API + store + i18n de la pantalla (FMT-03 Task 1)"
```

---

### Task 2: `FormatoCard.vue` (tarjeta de un formato)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/tickets/components/formatos/FormatoCard.vue`
- Test: `app/javascript/dashboard/routes/dashboard/tickets/components/formatos/specs/FormatoCard.spec.js`

**Interfaces:**
- Consumes: componentes `Button`, `Dialog` de components-next; i18n `TICKETS.FORMATOS.*`.
- Produces: componente que recibe props `formato` (`{ id, codigo, nombre, activa_id, versiones: [{id,version,estado,marcadores}] }`), `esAdmin` (bool), `desconocidos` (array de strings, opcional); emite `subir(formato)`, `activar(plantillaId)`, `descartar(plantillaId)`, `descargar(plantillaId)`, `previsualizar(plantillaId)`.

- [ ] **Step 1: Escribir el spec (falla)**

`.../formatos/specs/FormatoCard.spec.js`:
```js
import { mount } from '@vue/test-utils';
import FormatoCard from '../FormatoCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const formatoConActiva = {
  id: 1, codigo: 'visita_tecnica', nombre: 'Visita técnica',
  activa_id: 10, versiones: [{ id: 10, version: 3, estado: 'activa', marcadores: ['CLIENTE'] }],
};
const formatoSinActiva = { id: 2, codigo: 'recoleccion', nombre: 'Recolección', activa_id: null, versiones: [] };

const montar = (props) => mount(FormatoCard, {
  props: { esAdmin: true, ...props },
  global: { stubs: { Button: { template: '<button data-testid="btn"><slot />{{ label }}</button>', props: ['label'] }, Dialog: true } },
});

describe('FormatoCard', () => {
  it('muestra el nombre del formato', () => {
    const wrapper = montar({ formato: formatoConActiva });
    expect(wrapper.text()).toContain('Visita técnica');
  });

  it('un formato sin activa avisa que no tiene plantilla', () => {
    const wrapper = montar({ formato: formatoSinActiva });
    expect(wrapper.find('[data-testid="sin-plantilla"]').exists()).toBe(true);
  });

  it('un agente (no admin) no ve el boton de subir', () => {
    const wrapper = montar({ formato: formatoConActiva, esAdmin: false });
    expect(wrapper.find('[data-testid="btn-subir"]').exists()).toBe(false);
  });

  it('muestra los marcadores desconocidos del 422', () => {
    const wrapper = montar({ formato: formatoConActiva, desconocidos: ['CLEINTE'] });
    expect(wrapper.find('[data-testid="desconocidos"]').text()).toContain('CLEINTE');
  });

  it('emite subir cuando el admin elige un archivo', async () => {
    const wrapper = montar({ formato: formatoConActiva });
    const input = wrapper.find('[data-testid="input-archivo"]');
    Object.defineProperty(input.element, 'files', { value: [new File(['x'], 'p.docx')] });
    await input.trigger('change');
    expect(wrapper.emitted('subir')).toBeTruthy();
  });
});
```

- [ ] **Step 2: Correr y ver que falla**

Run: `docker compose exec vite pnpm test app/javascript/dashboard/routes/dashboard/tickets/components/formatos/specs/FormatoCard.spec.js`
Expected: FAIL (no existe `FormatoCard.vue`).

- [ ] **Step 3: Implementar `FormatoCard.vue`**

```vue
<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  formato: { type: Object, required: true },
  esAdmin: { type: Boolean, default: false },
  desconocidos: { type: Array, default: () => [] },
});
const emit = defineEmits(['subir', 'activar', 'descartar', 'descargar', 'previsualizar']);
const { t } = useI18n();

const archivoRef = ref(null);
const dialogoActivar = ref(null);

const activa = computed(() =>
  props.formato.versiones.find(v => v.id === props.formato.activa_id)
);
const borrador = computed(() => props.formato.versiones.find(v => v.estado === 'borrador'));

const abrirSelector = () => archivoRef.value.click();
const alElegirArchivo = event => {
  const [archivo] = event.target.files;
  event.target.value = '';
  if (archivo) emit('subir', { formato: props.formato, archivo });
};
const confirmarActivar = () => {
  if (borrador.value) emit('activar', borrador.value.id);
  dialogoActivar.value.close();
};
</script>

<template>
  <div class="p-4 border rounded-lg flex flex-col gap-2" :data-testid="`card-${formato.codigo}`">
    <h3 class="font-medium">{{ formato.nombre }}</h3>

    <p v-if="activa" class="text-sm text-n-slate-11">
      {{ t('TICKETS.FORMATOS.VERSION_ACTIVA', { version: activa.version, fecha: '', quien: '' }) }}
    </p>
    <p v-else data-testid="sin-plantilla" class="text-sm text-n-ruby-11">
      {{ t('TICKETS.FORMATOS.SIN_PLANTILLA') }}
    </p>

    <ul v-if="desconocidos.length" data-testid="desconocidos" class="text-sm text-n-ruby-11">
      <li>{{ t('TICKETS.FORMATOS.DESCONOCIDOS') }}</li>
      <li v-for="m in desconocidos" :key="m">{{ m }}</li>
    </ul>

    <div class="flex gap-2 flex-wrap">
      <Button v-if="activa" sm faded :label="t('TICKETS.FORMATOS.VISTA_PREVIA')"
              data-testid="btn-previa" @click="emit('previsualizar', activa.id)" />
      <Button v-if="activa" sm faded :label="t('TICKETS.FORMATOS.DESCARGAR')"
              data-testid="btn-descargar" @click="emit('descargar', activa.id)" />
      <template v-if="esAdmin">
        <Button sm :label="t('TICKETS.FORMATOS.SUBIR')" data-testid="btn-subir" @click="abrirSelector" />
        <Button v-if="borrador" sm ruby :label="t('TICKETS.FORMATOS.ACTIVAR')"
                data-testid="btn-activar" @click="dialogoActivar.open()" />
        <Button v-if="borrador" sm ghost :label="t('TICKETS.FORMATOS.DESCARTAR')"
                data-testid="btn-descartar" @click="emit('descartar', borrador.id)" />
      </template>
    </div>

    <input ref="archivoRef" type="file" accept=".docx" class="hidden"
           data-testid="input-archivo" @change="alElegirArchivo" />

    <Dialog ref="dialogoActivar" type="alert" :title="t('TICKETS.FORMATOS.ACTIVAR')"
            :description="t('TICKETS.FORMATOS.ACTIVAR_CONFIRMACION')" @confirm="confirmarActivar" />
  </div>
</template>
```
> Verifica los imports y props exactos de `Button`/`Dialog` contra `PqrCatalogosPage.vue` (rutas y nombres de prop como `sm`, `ruby`, `faded`, `ghost`). Ajusta clases de color a las que use el proyecto.

- [ ] **Step 4: Correr el spec (pasa)**

Run: `docker compose exec vite pnpm test .../formatos/specs/FormatoCard.spec.js`
Expected: PASS (5 tests).

- [ ] **Step 5: eslint + guardián + commit**

```
docker compose exec vite pnpm eslint app/javascript/dashboard/routes/dashboard/tickets/components/formatos/
git add -A && git commit --no-verify -m "feat(formatos): FormatoCard con acciones y 422 (FMT-03 Task 2)"
```

---

### Task 3: `FormatosPanel.vue` (panel: tarjetas + marcadores + vista previa)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/tickets/components/formatos/FormatosPanel.vue`
- Test: `.../formatos/specs/FormatosPanel.spec.js`

**Interfaces:**
- Consumes: store `helic3Formatos` (getters/actions de Task 1), `FormatoCard` (Task 2), `navigator.clipboard`.
- Produces: el panel completo que se monta en PqrCatalogosPage (Task 4).

- [ ] **Step 1: Escribir el spec (falla)**

`.../formatos/specs/FormatosPanel.spec.js`:
```js
import { mount, flushPromises } from '@vue/test-utils';
import FormatosPanel from '../FormatosPanel.vue';

const dispatch = vi.fn(() => Promise.resolve());
const getters = {
  'helic3Formatos/getFormatos': { value: [
    { id: 1, codigo: 'visita_tecnica', nombre: 'Visita', activa_id: 10,
      versiones: [{ id: 10, version: 1, estado: 'activa', marcadores: ['CLIENTE'] }] },
  ] },
  'helic3Formatos/getMarcadores': { value: { CLIENTE: { descripcion: 'd', ejemplo: 'e' } } },
  'helic3Formatos/getUIFlags': { value: { isFetching: false, isSaving: false } },
  getCurrentRole: { value: 'administrator' },
};
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: name => getters[name],
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const montar = () => mount(FormatosPanel, {
  global: { stubs: { FormatoCard: { template: '<div data-testid="card" />', props: ['formato', 'esAdmin', 'desconocidos'] } } },
});

describe('FormatosPanel', () => {
  beforeEach(() => { dispatch.mockClear(); });

  it('carga formatos y marcadores al montar', () => {
    montar();
    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/fetchFormatos');
    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/fetchMarcadores');
  });

  it('pinta una tarjeta por formato', () => {
    const wrapper = montar();
    expect(wrapper.findAll('[data-testid="card"]')).toHaveLength(1);
  });

  it('copiar un marcador escribe {{NOMBRE}} en el portapapeles', async () => {
    const writeText = vi.fn(() => Promise.resolve());
    Object.assign(navigator, { clipboard: { writeText } });
    const wrapper = montar();
    await wrapper.find('[data-testid="copiar-CLIENTE"]').trigger('click');
    expect(writeText).toHaveBeenCalledWith('{{CLIENTE}}');
  });

  it('subir despacha la accion del store', async () => {
    const wrapper = montar();
    wrapper.findComponent({ name: 'FormatoCard' }).vm.$emit('subir',
      { formato: getters['helic3Formatos/getFormatos'].value[0], archivo: new File(['x'], 'p.docx') });
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/subirPlantilla', expect.anything());
  });

  it('un fallo al previsualizar no rompe el panel (Review Focus 4)', async () => {
    dispatch.mockImplementation(accion =>
      accion === 'helic3Formatos/vistaPrevia' ? Promise.reject(new Error('x')) : Promise.resolve());
    const wrapper = montar();
    wrapper.findComponent({ name: 'FormatoCard' }).vm.$emit('previsualizar', 10);
    await flushPromises();
    expect(wrapper.exists()).toBe(true);
    expect(wrapper.find('[data-testid="iframe-previa"]').exists()).toBe(false);
  });
});
```

- [ ] **Step 2: Correr y ver que falla**

Run: `docker compose exec vite pnpm test .../formatos/specs/FormatosPanel.spec.js`
Expected: FAIL (no existe `FormatosPanel.vue`).

- [ ] **Step 3: Implementar `FormatosPanel.vue`**

```vue
<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import FormatoCard from './FormatoCard.vue';

const { t } = useI18n();
const store = useStore();
const formatos = useMapGetter('helic3Formatos/getFormatos');
const marcadores = useMapGetter('helic3Formatos/getMarcadores');
const currentRole = useMapGetter('getCurrentRole');
const esAdmin = computed(() => currentRole.value === 'administrator');

const desconocidosPorFormato = ref({});
const urlPrevia = ref(null);

onMounted(() => {
  store.dispatch('helic3Formatos/fetchFormatos');
  store.dispatch('helic3Formatos/fetchMarcadores');
});
onBeforeUnmount(() => { if (urlPrevia.value) URL.revokeObjectURL(urlPrevia.value); });

const conAviso = async accion => {
  try { return await accion(); }
  catch (error) {
    if (error?.response?.status === 401) useAlert(t('TICKETS.FORMATOS.FORBIDDEN'));
    else useAlert(t('TICKETS.FORMATOS.ERROR'));
    throw error;
  }
};

const subir = async ({ formato, archivo }) => {
  const formData = new FormData();
  formData.append('archivo', archivo);
  desconocidosPorFormato.value = { ...desconocidosPorFormato.value, [formato.id]: [] };
  try {
    await store.dispatch('helic3Formatos/subirPlantilla', { formatoId: formato.id, formData });
    useAlert(t('TICKETS.FORMATOS.GUARDADO'));
  } catch (error) {
    const errores = error?.response?.data?.errores || [];
    if (error?.response?.status === 422) {
      desconocidosPorFormato.value = { ...desconocidosPorFormato.value, [formato.id]: errores };
    } else {
      useAlert(t('TICKETS.FORMATOS.ERROR'));
    }
  }
};

const activar = id => conAviso(() => store.dispatch('helic3Formatos/activar', id)).then(() => useAlert(t('TICKETS.FORMATOS.GUARDADO')));
const descartar = id => conAviso(() => store.dispatch('helic3Formatos/descartar', id));

const previsualizar = plantillaId => conAviso(async () => {
  const blob = await store.dispatch('helic3Formatos/vistaPrevia', plantillaId);
  if (urlPrevia.value) URL.revokeObjectURL(urlPrevia.value);
  urlPrevia.value = URL.createObjectURL(blob);
});

const descargar = plantillaId => conAviso(async () => {
  const blob = await store.dispatch('helic3Formatos/descargarOriginal', plantillaId);
  window.open(URL.createObjectURL(blob), '_blank');
});

const copiar = async nombre => {
  await navigator.clipboard.writeText(`{{${nombre}}}`);
  useAlert(t('TICKETS.FORMATOS.MARCADORES.COPIADO'));
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <FormatoCard
      v-for="formato in formatos"
      :key="formato.id"
      :formato="formato"
      :es-admin="esAdmin"
      :desconocidos="desconocidosPorFormato[formato.id] || []"
      @subir="subir"
      @activar="activar"
      @descartar="descartar"
      @descargar="descargar"
      @previsualizar="previsualizar"
    />

    <div v-if="urlPrevia" class="flex flex-col gap-2">
      <div class="flex justify-between items-center">
        <h3 class="font-medium">{{ t('TICKETS.FORMATOS.VISTA_PREVIA') }}</h3>
        <Button sm faded :label="t('TICKETS.FORMATOS.ABRIR_NUEVA_PESTANA')" @click="window.open(urlPrevia, '_blank')" />
      </div>
      <iframe :src="urlPrevia" class="w-full h-[600px] border rounded" data-testid="iframe-previa" />
    </div>

    <details class="border rounded-lg p-3">
      <summary class="cursor-pointer font-medium">{{ t('TICKETS.FORMATOS.MARCADORES.TITLE') }}</summary>
      <ul class="mt-2 flex flex-col gap-1">
        <li v-for="(meta, nombre) in marcadores" :key="nombre" class="flex items-center gap-2 text-sm">
          <code>{{ '{{' + nombre + '}}' }}</code>
          <span class="text-n-slate-11">{{ meta.descripcion }}</span>
          <button :data-testid="`copiar-${nombre}`" class="text-n-blue-11" @click="copiar(nombre)">
            {{ t('TICKETS.FORMATOS.MARCADORES.COPIAR') }}
          </button>
        </li>
      </ul>
    </details>
  </div>
</template>
```
> Ajusta imports/clases a los reales del proyecto (rutas de `useStore`/`useMapGetter`/`useAlert`, clases de color `n-*`). El `window.open` en template puede requerir un método; si eslint se queja, muévelo a una función `abrirPrevia`.

- [ ] **Step 4: Correr el spec (pasa)**

Run: `docker compose exec vite pnpm test .../formatos/specs/FormatosPanel.spec.js`
Expected: PASS (4 tests).

- [ ] **Step 5: eslint + guardián + commit**

```
docker compose exec vite pnpm eslint app/javascript/dashboard/routes/dashboard/tickets/components/formatos/
git add -A && git commit --no-verify -m "feat(formatos): FormatosPanel con vista previa y marcadores (FMT-03 Task 3)"
```

---

### Task 4: Integrar la pestaña en `PqrCatalogosPage.vue`

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/tickets/pages/PqrCatalogosPage.vue`

**Interfaces:**
- Consumes: `FormatosPanel` (Task 3).

- [ ] **Step 1: Leer la estructura del menú interno**

Lee `PqrCatalogosPage.vue` para ver cómo define su menú lateral interno (la variable `tabActivo` y la lista de entradas que incluye «Parámetros»). Identifica dónde se renderiza el contenido según `tabActivo`.

- [ ] **Step 2: Añadir la entrada «Formatos»**

Agrega una entrada `{ id: 'formatos', label: t('TICKETS.FORMATOS.TITLE') }` a la lista del menú interno (junto a la de «Parámetros»), siguiendo el formato exacto que uses esa lista.

- [ ] **Step 3: Montar el panel**

Importa `FormatosPanel` y renderízalo cuando `tabActivo === 'formatos'`:
```vue
import FormatosPanel from '../components/formatos/FormatosPanel.vue';
...
<FormatosPanel v-else-if="tabActivo === 'formatos'" />
```
(Encájalo en el mismo bloque condicional donde hoy se decide entre catálogos y «Parámetros».)

- [ ] **Step 4: eslint + verificación visual**

Run: `docker compose exec vite pnpm eslint app/javascript/dashboard/routes/dashboard/tickets/pages/PqrCatalogosPage.vue`
Luego `docker compose restart vite` y abrir Catálogos → pestaña «Formatos» para ver las tarjetas.

- [ ] **Step 5: Guardián + commit**

```
git add -A && git commit --no-verify -m "feat(formatos): pestaña Formatos en Catalogos (FMT-03 Task 4)"
```

---

### Task 5: Verificación final

- [ ] **Step 1: Suite de los componentes de formatos**

Run: `docker compose exec vite pnpm test app/javascript/dashboard/routes/dashboard/tickets/components/formatos/`
Expected: todos verdes.

- [ ] **Step 2: eslint de todo lo tocado**

Run: `docker compose exec vite pnpm eslint app/javascript/dashboard/routes/dashboard/tickets/ app/javascript/dashboard/api/helic3/ app/javascript/dashboard/store/modules/helic3Formatos.js`
Expected: sin errores.

- [ ] **Step 3: Frontera (vacío = ok)**

Run: `git diff --name-only origin/dev -- package.json pnpm-lock.yaml app/javascript/dashboard/routes/dashboard/settings/settings.routes.js`
Expected: vacío.

- [ ] **Step 4: Verificación visual + capturas**

`docker compose restart vite`; abrir Catálogos → «Formatos»; probar subir/activar con el admin; capturar en tema Nogal y tema por defecto (CA6/CA7).

## Notas de ejecución

- **Secuencia:** FMT-03 se mergea después de FMT-02; la rama parte de FMT-02.
- **Servicio de pnpm/eslint/test:** confirmar el nombre del contenedor donde corre pnpm (puede ser `vite` u otro); ajustar los comandos `docker compose exec <servicio> pnpm ...`.
- **Imports de componentes:** los ejemplos usan rutas tipo `dashboard/components-next/...` y `dashboard/composables/...`; confirmar los alias exactos contra `PqrCatalogosPage.vue` antes de dar por buena cada importación.
