<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import FormatoCard from './FormatoCard.vue';

// FMT-03: panel de la pestana Formatos. Es el CONTENEDOR: habla con el store, arma la
// vista previa (blob -> URL) y copia marcadores. Las tarjetas solo emiten eventos.
const { t } = useI18n();
const store = useStore();
const formatos = useMapGetter('helic3Formatos/getFormatos');
const marcadores = useMapGetter('helic3Formatos/getMarcadores');
const currentRole = useMapGetter('getCurrentRole');
const esAdmin = computed(() => currentRole.value === 'administrator');

const desconocidosPorFormato = ref({});
const urlPrevia = ref(null);

// FMT-06: alta de formato nuevo (Karen, sin devs).
const dialogoNuevo = ref(null);
const nuevoNombre = ref('');
const nuevoCodigo = ref('');

onMounted(() => {
  store.dispatch('helic3Formatos/fetchFormatos');
  store.dispatch('helic3Formatos/fetchMarcadores');
});
onBeforeUnmount(() => {
  if (urlPrevia.value) URL.revokeObjectURL(urlPrevia.value);
});

// corre `accion`; si falla, muestra un aviso (401 = sin permiso) y lo traga.
const conAviso = async accion => {
  try {
    return await accion();
  } catch (error) {
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.FORMATOS.FORBIDDEN')
        : t('TICKETS.FORMATOS.ERROR')
    );
    return undefined;
  }
};

const subir = async ({ formato, archivo }) => {
  const formData = new FormData();
  formData.append('archivo', archivo);
  desconocidosPorFormato.value = {
    ...desconocidosPorFormato.value,
    [formato.id]: [],
  };
  try {
    await store.dispatch('helic3Formatos/subirPlantilla', {
      formatoId: formato.id,
      formData,
    });
    useAlert(t('TICKETS.FORMATOS.GUARDADO'));
  } catch (error) {
    if (error?.response?.status === 422) {
      desconocidosPorFormato.value = {
        ...desconocidosPorFormato.value,
        [formato.id]: error.response.data?.errores || [],
      };
    } else {
      useAlert(t('TICKETS.FORMATOS.ERROR'));
    }
  }
};

const activar = plantillaId =>
  conAviso(async () => {
    await store.dispatch('helic3Formatos/activar', plantillaId);
    useAlert(t('TICKETS.FORMATOS.GUARDADO'));
  });

const descartar = plantillaId =>
  conAviso(() => store.dispatch('helic3Formatos/descartar', plantillaId));

const previsualizar = plantillaId =>
  conAviso(async () => {
    const blob = await store.dispatch(
      'helic3Formatos/vistaPrevia',
      plantillaId
    );
    if (urlPrevia.value) URL.revokeObjectURL(urlPrevia.value);
    urlPrevia.value = URL.createObjectURL(blob);
  });

const descargar = plantillaId =>
  conAviso(async () => {
    const blob = await store.dispatch(
      'helic3Formatos/descargarOriginal',
      plantillaId
    );
    window.open(URL.createObjectURL(blob), '_blank');
  });

const abrirPreviaNuevaPestana = () => {
  if (urlPrevia.value) window.open(urlPrevia.value, '_blank');
};

// texto del marcador tal como se pega en Word; en metodo para no meter {{ }} en el template.
const comoMarcador = nombre => `{{${nombre}}}`;

const copiar = async nombre => {
  await navigator.clipboard.writeText(comoMarcador(nombre));
  useAlert(t('TICKETS.FORMATOS.MARCADORES.COPIADO'));
};

// FMT-06: codigo a partir del nombre (sin tildes, minusculas, guion bajo) para
// que Karen solo escriba el nombre; puede sobreescribirlo si quiere.
const comoCodigo = nombre =>
  (nombre || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

const abrirNuevo = () => {
  nuevoNombre.value = '';
  nuevoCodigo.value = '';
  dialogoNuevo.value?.open();
};

const crearFormato = async () => {
  const codigo = (nuevoCodigo.value || comoCodigo(nuevoNombre.value)).trim();
  if (!nuevoNombre.value.trim() || !codigo) return;
  try {
    await store.dispatch('helic3Formatos/crearFormato', {
      nombre: nuevoNombre.value.trim(),
      codigo,
    });
    useAlert(t('TICKETS.FORMATOS.CREADO'));
    dialogoNuevo.value?.close();
  } catch (error) {
    useAlert(error?.response?.data?.error || t('TICKETS.FORMATOS.ERROR'));
  }
};

const desactivar = formatoId =>
  conAviso(async () => {
    await store.dispatch('helic3Formatos/desactivarFormato', formatoId);
    useAlert(t('TICKETS.FORMATOS.DESACTIVADO'));
  });
</script>

<template>
  <div class="flex flex-col gap-4">
    <div v-if="esAdmin" class="flex justify-end">
      <Button
        sm
        data-testid="btn-nuevo-formato"
        :label="t('TICKETS.FORMATOS.NUEVO')"
        @click="abrirNuevo"
      />
    </div>

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
      @desactivar="desactivar"
    />

    <div v-if="urlPrevia" class="flex flex-col gap-2">
      <div class="flex items-center justify-between">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('TICKETS.FORMATOS.VISTA_PREVIA') }}
        </h3>
        <Button
          sm
          faded
          :label="t('TICKETS.FORMATOS.ABRIR_NUEVA_PESTANA')"
          @click="abrirPreviaNuevaPestana"
        />
      </div>
      <iframe
        :src="urlPrevia"
        data-testid="iframe-previa"
        class="w-full h-[600px] border border-n-weak rounded"
      />
    </div>

    <details class="p-3 border border-n-weak rounded-lg">
      <summary class="font-medium cursor-pointer text-n-slate-12">
        {{ t('TICKETS.FORMATOS.MARCADORES.TITLE') }}
      </summary>
      <ul class="flex flex-col gap-1 mt-2">
        <li
          v-for="(meta, nombre) in marcadores"
          :key="nombre"
          class="flex items-center gap-2 text-sm"
        >
          <code class="text-n-slate-12">{{ comoMarcador(nombre) }}</code>
          <span class="text-n-slate-11">{{ meta.descripcion }}</span>
          <button
            :data-testid="`copiar-${nombre}`"
            class="text-n-blue-11"
            @click="copiar(nombre)"
          >
            {{ t('TICKETS.FORMATOS.MARCADORES.COPIAR') }}
          </button>
        </li>
      </ul>
    </details>

    <Dialog
      ref="dialogoNuevo"
      :title="t('TICKETS.FORMATOS.NUEVO_TITULO')"
      :confirm-button-label="t('TICKETS.FORMATOS.CREAR')"
      :disable-confirm-button="!nuevoNombre.trim()"
      @confirm="crearFormato"
    >
      <div class="flex flex-col gap-3">
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('TICKETS.FORMATOS.NOMBRE') }}
          </span>
          <input
            v-model="nuevoNombre"
            data-testid="input-nombre"
            class="p-2 border rounded border-n-weak bg-n-alpha-black1"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('TICKETS.FORMATOS.CODIGO') }}
          </span>
          <input
            v-model="nuevoCodigo"
            :placeholder="comoCodigo(nuevoNombre)"
            data-testid="input-codigo"
            class="p-2 border rounded border-n-weak bg-n-alpha-black1"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('TICKETS.FORMATOS.CODIGO_AYUDA') }}
          </span>
        </label>
      </div>
    </Dialog>
  </div>
</template>
