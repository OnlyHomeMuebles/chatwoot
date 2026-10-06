<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
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
  </div>
</template>
