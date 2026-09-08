<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Catalogos y parametros editables (ADM-01). Karen edita el vocabulario y los
// tiempos del modulo sin consola. Lectura para agentes; solo los administradores
// editan (el backend rechaza con 401 si un agente intenta escribir).
const store = useStore();
const { t } = useI18n();

// tipos que Karen edita (los demas, en lectura, se agregan luego)
const TIPOS = [
  'motivos_pqr',
  'resultados',
  'detalles_tipificados',
  'procesos_garantia',
  'coberturas_ciudad',
];
const PARAMETROS = 'parametros';

const tabActivo = ref(TIPOS[0]);
const nuevo = ref({ nombre: '', codigo: '' });

const uiFlags = useMapGetter('pqrCatalogos/getUIFlags');
const getCatalogo = useMapGetter('pqrCatalogos/getCatalogo');
const parametros = useMapGetter('pqrCatalogos/getParametros');
const currentRole = useMapGetter('getCurrentRole');

const esAdmin = computed(() => currentRole.value === 'administrator');
const esParametros = computed(() => tabActivo.value === PARAMETROS);
const registros = computed(() => getCatalogo.value(tabActivo.value));

const cargar = () => {
  if (esParametros.value) {
    store.dispatch('pqrCatalogos/fetchParametros');
  } else {
    store.dispatch('pqrCatalogos/fetchCatalogo', tabActivo.value);
  }
};

onMounted(cargar);
watch(tabActivo, () => {
  nuevo.value = { nombre: '', codigo: '' };
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

const guardarNombre = (registro, nombre) =>
  conAviso(() =>
    store.dispatch('pqrCatalogos/updateCatalogo', {
      tipo: tabActivo.value,
      id: registro.id,
      data: { nombre },
    })
  );

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

const crear = () => {
  if (!nuevo.value.nombre || !nuevo.value.codigo) return;
  conAviso(async () => {
    await store.dispatch('pqrCatalogos/createCatalogo', {
      tipo: tabActivo.value,
      data: { ...nuevo.value },
    });
    nuevo.value = { nombre: '', codigo: '' };
  });
};

const guardarParametro = (parametro, valor) =>
  conAviso(() =>
    store.dispatch('pqrCatalogos/updateParametro', {
      id: parametro.id,
      data: { valor },
    })
  );
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
              {{ parametro.clave }}
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
      <div v-else class="flex flex-col max-w-3xl gap-3">
        <div
          v-for="registro in registros"
          :key="registro.id"
          class="flex items-center gap-3"
          :class="registro.activo ? '' : 'opacity-50'"
        >
          <Input
            :model-value="registro.nombre"
            :disabled="!esAdmin"
            class="flex-1"
            @blur="e => guardarNombre(registro, e.target.value)"
          />
          <span class="w-40 text-xs text-n-slate-11">{{
            registro.codigo
          }}</span>
          <Button
            :label="
              registro.activo
                ? t('TICKETS.ADMIN.DEACTIVATE')
                : t('TICKETS.ADMIN.ACTIVATE')
            "
            :disabled="!esAdmin"
            faded
            xs
            @click="alternarActivo(registro)"
          />
          <Button
            icon="i-lucide-trash-2"
            :disabled="!esAdmin"
            ghost
            ruby
            xs
            @click="eliminar(registro)"
          />
        </div>

        <div
          v-if="esAdmin"
          class="flex items-center gap-3 pt-3 mt-2 border-t border-n-weak"
        >
          <Input
            v-model="nuevo.nombre"
            :placeholder="t('TICKETS.ADMIN.NEW_NAME')"
            class="flex-1"
          />
          <Input
            v-model="nuevo.codigo"
            :placeholder="t('TICKETS.ADMIN.NEW_CODE')"
            class="w-40"
          />
          <Button
            :label="t('TICKETS.ADMIN.ADD')"
            icon="i-lucide-plus"
            sm
            :is-loading="uiFlags.isSaving"
            @click="crear"
          />
        </div>
      </div>
    </div>
  </div>
</template>
