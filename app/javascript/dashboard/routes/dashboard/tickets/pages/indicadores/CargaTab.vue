<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useCargasStore } from 'dashboard/store/helic3/cargas';

// IND-03 (parcial): "Carga de Datos". Hoy solo Facturas tiene parser real;
// Garantías/Peticiones/Devoluciones (IND-04) esperan a que se definan sus
// columnas con el Dash CX -- se muestran en el selector pero deshabilitadas,
// en vez de simularlas con datos falsos.
const { t } = useI18n();
const cargasStore = useCargasStore();

const cargando = computed(() => cargasStore.getUIFlags.isFetching);
const subiendo = computed(() => cargasStore.getUIFlags.isSubiendo);
const cargas = computed(() => cargasStore.getCargas);

const TIPOS = [
  { value: 'facturas', label: 'FACTURAS', disponible: true },
  { value: 'garantias', label: 'GARANTIAS', disponible: false },
  { value: 'peticiones', label: 'PETICIONES', disponible: false },
  { value: 'devoluciones', label: 'DEVOLUCIONES', disponible: false },
];
const tipoOptions = computed(() =>
  TIPOS.map(tipo => ({
    value: tipo.value,
    label: tipo.disponible
      ? t(`HELIC3_INDICADORES.CARGA.TIPO_${tipo.label}`)
      : t('HELIC3_INDICADORES.CARGA.TIPO_PENDIENTE', {
          tipo: t(`HELIC3_INDICADORES.CARGA.TIPO_${tipo.label}`),
        }),
    disabled: !tipo.disponible,
  }))
);

const MODOS = [
  { value: 'anexar', label: 'MODE_ANEXAR' },
  { value: 'sobrescribir', label: 'MODE_SOBRESCRIBIR' },
];
const modoOptions = computed(() =>
  MODOS.map(modo => ({
    value: modo.value,
    label: t(`HELIC3_INDICADORES.CARGA.${modo.label}`),
  }))
);

const tipo = ref('facturas');
const modo = ref('anexar');
const archivo = ref(null);
const inputArchivo = ref(null);

const columnasRequeridas = computed(() => {
  if (tipo.value !== 'facturas') return [];
  return ['Nro documento', 'Desc. C.O.', 'Fecha', 'Valor subtotal'];
});

const onArchivoSeleccionado = evento => {
  archivo.value = evento.target.files[0] || null;
};

const subir = async () => {
  if (!archivo.value) {
    useAlert(t('HELIC3_INDICADORES.CARGA.ARCHIVO_REQUERIDO'));
    return;
  }
  try {
    await cargasStore.subirArchivo({
      tipo: tipo.value,
      modo: modo.value,
      archivo: archivo.value,
    });
    useAlert(t('HELIC3_INDICADORES.CARGA.EXITO'));
    archivo.value = null;
    if (inputArchivo.value) inputArchivo.value.value = '';
  } catch (error) {
    const mensaje =
      error.response?.data?.error || t('HELIC3_INDICADORES.CARGA.ERROR');
    useAlert(mensaje);
  }
};

onMounted(() => cargasStore.fetchCargas());
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Formulario de carga -->
    <div class="p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1">
      <p class="font-semibold text-n-slate-12">
        {{ t('HELIC3_INDICADORES.CARGA.TITLE') }}
      </p>
      <p class="mt-1 mb-4 text-xs text-n-slate-11">
        {{ t('HELIC3_INDICADORES.CARGA.SUBTITLE') }}
      </p>

      <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
        <div class="min-w-0 space-y-1.5">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('HELIC3_INDICADORES.CARGA.TYPE_LABEL') }}
          </label>
          <Select
            v-model="tipo"
            :options="tipoOptions"
            :aria-label="t('HELIC3_INDICADORES.CARGA.TYPE_LABEL')"
          />
        </div>
        <div class="min-w-0 space-y-1.5">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('HELIC3_INDICADORES.CARGA.MODE_LABEL') }}
          </label>
          <Select
            v-model="modo"
            :options="modoOptions"
            :aria-label="t('HELIC3_INDICADORES.CARGA.MODE_LABEL')"
          />
        </div>
        <div class="min-w-0 space-y-1.5">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('HELIC3_INDICADORES.CARGA.FILE_LABEL') }}
          </label>
          <input
            ref="inputArchivo"
            type="file"
            accept=".csv,text/csv"
            class="w-full text-sm text-n-slate-11 file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:bg-n-alpha-2 file:text-n-slate-12 file:text-sm"
            @change="onArchivoSeleccionado"
          />
        </div>
      </div>

      <p v-if="columnasRequeridas.length" class="mt-3 text-xs text-n-slate-11">
        {{ t('HELIC3_INDICADORES.CARGA.REQUIRED_COLUMNS') }}
        <span class="font-medium text-n-slate-12">{{
          columnasRequeridas.join(', ')
        }}</span>
      </p>

      <div class="flex justify-end mt-4">
        <Button
          :label="t('HELIC3_INDICADORES.CARGA.UPLOAD_BUTTON')"
          icon="i-lucide-upload"
          :is-loading="subiendo"
          @click="subir"
        />
      </div>
    </div>

    <!-- Historial -->
    <div
      class="rounded-xl outline outline-1 outline-n-weak bg-n-solid-1 overflow-hidden"
    >
      <p class="p-4 font-semibold border-b border-n-weak text-n-slate-12">
        {{ t('HELIC3_INDICADORES.CARGA.HISTORY') }}
      </p>

      <div v-if="cargando" class="flex justify-center py-8">
        <Spinner :size="24" />
      </div>

      <p
        v-else-if="!cargas.length"
        class="py-8 text-sm text-center text-n-slate-11"
      >
        {{ t('HELIC3_INDICADORES.CARGA.EMPTY') }}
      </p>

      <table v-else class="w-full text-sm">
        <thead class="text-xs text-n-slate-11">
          <tr>
            <th class="px-4 py-2 text-left font-medium">
              {{ t('HELIC3_INDICADORES.CARGA.COL_FILE') }}
            </th>
            <th class="px-4 py-2 text-left font-medium">
              {{ t('HELIC3_INDICADORES.CARGA.COL_MODE') }}
            </th>
            <th class="px-4 py-2 text-left font-medium">
              {{ t('HELIC3_INDICADORES.CARGA.COL_STATUS') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ t('HELIC3_INDICADORES.CARGA.COL_READ') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ t('HELIC3_INDICADORES.CARGA.COL_INSERTED') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ t('HELIC3_INDICADORES.CARGA.COL_UPDATED') }}
            </th>
            <th class="px-4 py-2 text-right font-medium">
              {{ t('HELIC3_INDICADORES.CARGA.COL_SKIPPED') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="carga in cargas"
            :key="carga.id"
            class="border-t border-n-weak"
          >
            <td class="px-4 py-2 text-n-slate-11">
              {{ carga.nombre_archivo }}
            </td>
            <td class="px-4 py-2 text-n-slate-11">
              {{
                t(`HELIC3_INDICADORES.CARGA.MODE_${carga.modo.toUpperCase()}`)
              }}
            </td>
            <td class="px-4 py-2 text-n-slate-11">
              {{
                t(
                  `HELIC3_INDICADORES.CARGA.STATUS_${carga.estado.toUpperCase()}`
                )
              }}
            </td>
            <td class="px-4 py-2 text-right tabular-nums text-n-slate-11">
              {{ carga.filas_leidas }}
            </td>
            <td class="px-4 py-2 text-right tabular-nums text-n-teal-11">
              {{ carga.filas_insertadas }}
            </td>
            <td class="px-4 py-2 text-right tabular-nums text-n-slate-11">
              {{ carga.filas_actualizadas }}
            </td>
            <td class="px-4 py-2 text-right tabular-nums text-n-amber-11">
              {{ carga.filas_omitidas }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
