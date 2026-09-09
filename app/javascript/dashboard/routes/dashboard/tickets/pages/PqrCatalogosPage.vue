<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Catalogos y parametros editables (ADM-01). Karen edita el vocabulario, las
// marcas de comportamiento y los tiempos del modulo sin consola. Lectura para
// agentes; solo administradores editan (el backend rechaza con 401).
const store = useStore();
const { t } = useI18n();

const TIPOS = [
  'motivos_pqr',
  'resultados',
  'detalles_tipificados',
  'procesos_garantia',
  'coberturas_ciudad',
];
const PARAMETROS = 'parametros';

// Campos propios de cada catalogo, con el CONTROL resuelto por el tipo de columna
// (no por el nombre): abre_garantia es enum en motivos y booleano en resultados.
const ENUM_ABRE_GARANTIA = ['nunca', 'siempre', 'segun_analisis'];
const CAMPOS = {
  motivos_pqr: [
    { key: 'categoria_id', tipo: 'categoria', requerido: true },
    { key: 'abre_garantia', tipo: 'enum', opciones: ENUM_ABRE_GARANTIA },
    { key: 'plazo_dias_habiles', tipo: 'numero' },
  ],
  resultados: [
    { key: 'cierra_pqr', tipo: 'bool' },
    { key: 'abre_garantia', tipo: 'bool' },
    { key: 'aprobacion_humana', tipo: 'bool' },
  ],
  detalles_tipificados: [],
  procesos_garantia: [
    { key: 'es_terminal', tipo: 'bool' },
    { key: 'plazo_dias_habiles', tipo: 'numero' },
  ],
  coberturas_ciudad: [
    { key: 'tecnico_propio', tipo: 'bool' },
    { key: 'origen_ruta', tipo: 'texto' },
  ],
};

const tabActivo = ref(TIPOS[0]);
const nuevo = reactive({});

const uiFlags = useMapGetter('pqrCatalogos/getUIFlags');
const getCatalogo = useMapGetter('pqrCatalogos/getCatalogo');
const parametros = useMapGetter('pqrCatalogos/getParametros');
const currentRole = useMapGetter('getCurrentRole');
const catalogosPanel = useMapGetter('tickets/getCatalogos');

const esAdmin = computed(() => currentRole.value === 'administrator');
const esParametros = computed(() => tabActivo.value === PARAMETROS);
const registros = computed(() => getCatalogo.value(tabActivo.value));
const camposActivos = computed(() => CAMPOS[tabActivo.value] || []);

// Categorias para el selector de motivos (API-01 las trae embebidas en los motivos).
const categoriaOptions = computed(() => {
  const vistas = new Map();
  (catalogosPanel.value.motivos_pqr || []).forEach(m => {
    if (m.categoria) vistas.set(m.categoria.id, m.categoria);
  });
  return [...vistas.values()].map(c => ({ value: c.id, label: c.nombre }));
});

const enumOptions = campo =>
  campo.opciones.map(op => ({
    value: op,
    label: t(`TICKETS.ADMIN.ENUM.${op.toUpperCase()}`),
  }));

// Modelo editable por fila (para comparar y guardar solo si cambio).
const ediciones = ref({});
const soloCampos = registro => {
  const modelo = { nombre: registro.nombre };
  camposActivos.value.forEach(c => {
    modelo[c.key] = registro[c.key];
  });
  return modelo;
};
watch(
  registros,
  nuevos => {
    const mapa = {};
    nuevos.forEach(r => {
      mapa[r.id] = soloCampos(r);
    });
    ediciones.value = mapa;
  },
  { immediate: true }
);

const reiniciarNuevo = () => {
  const base = { nombre: '', codigo: '' };
  camposActivos.value.forEach(c => {
    base[c.key] = c.tipo === 'bool' ? false : '';
  });
  Object.keys(nuevo).forEach(k => delete nuevo[k]);
  Object.assign(nuevo, base);
};

const cargar = () => {
  if (esParametros.value) {
    store.dispatch('pqrCatalogos/fetchParametros');
  } else {
    store.dispatch('pqrCatalogos/fetchCatalogo', tabActivo.value);
  }
};

onMounted(() => {
  store
    .dispatch('tickets/getCatalogos')
    .catch(() => useAlert(t('TICKETS.ADMIN.ERROR')));
  reiniciarNuevo();
  cargar();
});

watch(tabActivo, () => {
  reiniciarNuevo();
  cargar();
});

const tabs = computed(() => [
  ...TIPOS.map(tipo => ({
    value: tipo,
    label: t(`TICKETS.ADMIN.TABS.${tipo.toUpperCase()}`),
  })),
  { value: PARAMETROS, label: t('TICKETS.ADMIN.TABS.PARAMETROS') },
]);

const conAviso = async accion => {
  try {
    await accion();
    useAlert(t('TICKETS.ADMIN.SAVED'));
  } catch (error) {
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.ADMIN.FORBIDDEN')
        : error?.response?.data?.error || t('TICKETS.ADMIN.ERROR')
    );
  }
};

// Guarda solo los campos que cambiaron; si no cambio nada, no despacha.
const guardar = registro => {
  const modelo = ediciones.value[registro.id];
  const cambios = {};
  Object.entries(modelo).forEach(([clave, valor]) => {
    if (valor !== registro[clave]) cambios[clave] = valor;
  });
  if (Object.keys(cambios).length === 0) return;
  conAviso(() =>
    store.dispatch('pqrCatalogos/updateCatalogo', {
      tipo: tabActivo.value,
      id: registro.id,
      data: cambios,
    })
  );
};

const alternarActivo = registro =>
  conAviso(() =>
    store.dispatch('pqrCatalogos/updateCatalogo', {
      tipo: tabActivo.value,
      id: registro.id,
      data: { activo: !registro.activo },
    })
  );

const eliminar = registro =>
  conAviso(() =>
    store.dispatch('pqrCatalogos/deleteCatalogo', {
      tipo: tabActivo.value,
      id: registro.id,
    })
  );

const puedeCrear = computed(() => {
  if (!nuevo.nombre || !nuevo.codigo) return false;
  return camposActivos.value.every(c => !c.requerido || nuevo[c.key]);
});

const crear = () => {
  if (!puedeCrear.value) return;
  conAviso(async () => {
    await store.dispatch('pqrCatalogos/createCatalogo', {
      tipo: tabActivo.value,
      data: { ...nuevo },
    });
    reiniciarNuevo();
  });
};

// Aviso ANTES de guardar un parametro obligatorio vacio (no solo el error del back).
const guardarParametro = (parametro, valor) => {
  if (valor === '' || valor === null) {
    useAlert(t('TICKETS.ADMIN.PARAM_REQUIRED', { param: parametro.etiqueta }));
    return;
  }
  if (valor === parametro.valor) return;
  conAviso(() =>
    store.dispatch('pqrCatalogos/updateParametro', {
      id: parametro.id,
      data: { valor },
    })
  );
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('TICKETS.ADMIN.TITLE') }}
      </h1>
      <span v-if="!esAdmin" class="text-sm text-n-amber-11">
        {{ t('TICKETS.ADMIN.READ_ONLY') }}
      </span>
    </header>

    <div class="flex flex-wrap gap-2 px-6 py-3 border-b border-n-weak">
      <Button
        v-for="tab in tabs"
        :key="tab.value"
        :label="tab.label"
        :color="tabActivo === tab.value ? 'blue' : 'slate'"
        :faded="tabActivo !== tab.value"
        sm
        @click="tabActivo = tab.value"
      />
    </div>

    <div class="flex-1 p-6 overflow-y-auto">
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        <Spinner :size="24" />
      </div>

      <!-- Parametros -->
      <div v-else-if="esParametros" class="flex flex-col max-w-2xl gap-3">
        <div
          v-for="parametro in parametros"
          :key="parametro.id"
          class="flex items-center gap-3"
        >
          <div class="flex-1">
            <p class="mb-0 text-sm font-medium text-n-slate-12">
              {{ parametro.etiqueta }}
            </p>
            <p class="mb-0 text-xs text-n-slate-11">{{ parametro.unidad }}</p>
          </div>
          <Input
            :model-value="parametro.valor"
            :disabled="!esAdmin"
            class="w-32"
            @blur="e => guardarParametro(parametro, e.target.value)"
          />
        </div>
      </div>

      <!-- Catalogo -->
      <div v-else class="flex flex-col gap-3">
        <template v-for="registro in registros" :key="registro.id">
          <div
            v-if="ediciones[registro.id]"
            class="flex flex-wrap items-center gap-3 p-3 border rounded-lg border-n-weak"
            :class="registro.activo ? '' : 'opacity-50'"
          >
            <Input
              v-model="ediciones[registro.id].nombre"
              :disabled="!esAdmin"
              class="min-w-40 flex-1"
            />
            <span class="text-xs text-n-slate-11">{{ registro.codigo }}</span>

            <!-- Marcas de comportamiento, control por tipo de columna -->
            <template v-for="campo in camposActivos" :key="campo.key">
              <label
                v-if="campo.tipo === 'bool'"
                class="flex items-center gap-1 text-xs cursor-pointer text-n-slate-11"
                :title="t(`TICKETS.ADMIN.FLAGS.${campo.key.toUpperCase()}`)"
              >
                <input
                  v-model="ediciones[registro.id][campo.key]"
                  type="checkbox"
                  :disabled="!esAdmin"
                />
                {{ t(`TICKETS.ADMIN.FLAGS.${campo.key.toUpperCase()}`) }}
              </label>
              <Select
                v-else-if="campo.tipo === 'enum'"
                v-model="ediciones[registro.id][campo.key]"
                :options="enumOptions(campo)"
                :disabled="!esAdmin"
                class="w-40"
              />
              <Select
                v-else-if="campo.tipo === 'categoria'"
                v-model="ediciones[registro.id][campo.key]"
                :options="categoriaOptions"
                :disabled="!esAdmin"
                class="w-40"
              />
              <Input
                v-else
                v-model="ediciones[registro.id][campo.key]"
                :type="campo.tipo === 'numero' ? 'number' : 'text'"
                :disabled="!esAdmin"
                :placeholder="
                  t(`TICKETS.ADMIN.FLAGS.${campo.key.toUpperCase()}`)
                "
                class="w-32"
              />
            </template>

            <div v-if="esAdmin" class="flex items-center gap-2 ml-auto">
              <Button
                :label="t('TICKETS.ADMIN.SAVE')"
                sm
                @click="guardar(registro)"
              />
              <Button
                :label="
                  registro.activo
                    ? t('TICKETS.ADMIN.DEACTIVATE')
                    : t('TICKETS.ADMIN.ACTIVATE')
                "
                faded
                xs
                @click="alternarActivo(registro)"
              />
              <Button
                icon="i-lucide-trash-2"
                ghost
                ruby
                xs
                @click="eliminar(registro)"
              />
            </div>
          </div>
        </template>

        <!-- Alta: nombre, codigo y los campos propios del catalogo -->
        <div
          v-if="esAdmin"
          class="flex flex-wrap items-center gap-3 pt-3 mt-2 border-t border-n-weak"
        >
          <Input
            v-model="nuevo.nombre"
            :placeholder="t('TICKETS.ADMIN.NEW_NAME')"
            class="min-w-40 flex-1"
          />
          <Input
            v-model="nuevo.codigo"
            :placeholder="t('TICKETS.ADMIN.NEW_CODE')"
            class="w-40"
          />
          <template v-for="campo in camposActivos" :key="`nuevo-${campo.key}`">
            <label
              v-if="campo.tipo === 'bool'"
              class="flex items-center gap-1 text-xs cursor-pointer text-n-slate-11"
            >
              <input v-model="nuevo[campo.key]" type="checkbox" />
              {{ t(`TICKETS.ADMIN.FLAGS.${campo.key.toUpperCase()}`) }}
            </label>
            <Select
              v-else-if="campo.tipo === 'enum'"
              v-model="nuevo[campo.key]"
              :options="enumOptions(campo)"
              class="w-40"
            />
            <Select
              v-else-if="campo.tipo === 'categoria'"
              v-model="nuevo[campo.key]"
              :options="categoriaOptions"
              :placeholder="t('TICKETS.ADMIN.FLAGS.CATEGORIA_ID')"
              class="w-40"
            />
            <Input
              v-else
              v-model="nuevo[campo.key]"
              :type="campo.tipo === 'numero' ? 'number' : 'text'"
              :placeholder="t(`TICKETS.ADMIN.FLAGS.${campo.key.toUpperCase()}`)"
              class="w-32"
            />
          </template>
          <Button
            :label="t('TICKETS.ADMIN.ADD')"
            icon="i-lucide-plus"
            sm
            :disabled="!puedeCrear"
            :is-loading="uiFlags.isSaving"
            @click="crear"
          />
        </div>
      </div>
    </div>
  </div>
</template>
