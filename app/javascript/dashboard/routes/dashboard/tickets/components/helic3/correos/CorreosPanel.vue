<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PlantillaCorreoCard from './PlantillaCorreoCard.vue';

// COR-04: panel de la pestana Correos. Es el CONTENEDOR: habla con el store,
// arma la vista previa (asunto/cuerpo_html -> iframe) y decide para que
// procesos falta plantilla todavia. Las tarjetas solo emiten eventos.
const { t } = useI18n();
const store = useStore();
const plantillas = useMapGetter('helic3Correos/getPlantillas');
const marcadores = useMapGetter('helic3Formatos/getMarcadores');
const procesos = useMapGetter('pqrCatalogos/getCatalogo');
const currentRole = useMapGetter('getCurrentRole');
const esAdmin = computed(() => currentRole.value === 'administrator');

const previa = ref(null);

onMounted(() => {
  store.dispatch('helic3Correos/fetchPlantillas');
  store.dispatch('helic3Formatos/fetchMarcadores');
  store.dispatch('pqrCatalogos/fetchCatalogo', 'procesos_garantia');
});

// corre `accion`; si falla, muestra un aviso (401 = sin permiso) y lo traga.
const conAviso = async accion => {
  try {
    return await accion();
  } catch (error) {
    useAlert(
      error?.response?.status === 401
        ? t('TICKETS.CORREOS.FORBIDDEN')
        : t('TICKETS.CORREOS.ERROR')
    );
    return undefined;
  }
};

const guardar = ({ id, data }) =>
  conAviso(async () => {
    await store.dispatch('helic3Correos/actualizarPlantilla', { id, data });
    useAlert(t('TICKETS.CORREOS.GUARDADO'));
  });

const alternarActivo = plantilla =>
  conAviso(() =>
    store.dispatch('helic3Correos/actualizarPlantilla', {
      id: plantilla.id,
      data: { activo: !plantilla.activo },
    })
  );

const previsualizar = id =>
  conAviso(async () => {
    previa.value = await store.dispatch('helic3Correos/vistaPrevia', id);
  });

const enviarPrueba = id =>
  conAviso(async () => {
    await store.dispatch('helic3Correos/enviarPrueba', id);
    useAlert(t('TICKETS.CORREOS.PRUEBA_ENVIADA'));
  });

// procesos de garantia (activos) que todavia no tienen plantilla propia: la
// unica forma de crear una (p.ej. garantia_negada, D2) sin pedirselo a devs.
const procesosSinPlantilla = computed(() => {
  const cubiertos = new Set(
    plantillas.value
      .filter(p => p.proceso_garantia_id)
      .map(p => p.proceso_garantia_id)
  );
  return (procesos.value('procesos_garantia') || []).filter(
    p => p.activo && !cubiertos.has(p.id)
  );
});

const tieneCierreCaso = computed(() =>
  plantillas.value.some(p => p.disparador === 'cierre_caso')
);

// COR-04: alta de una plantilla para un proceso (o para el cierre de caso)
// que todavia no tiene correo.
const dialogoNuevo = ref(null);
const nuevoProceso = ref(null);
const nuevoAsunto = ref('');
const nuevoCuerpo = ref('');

const abrirNuevo = proceso => {
  nuevoProceso.value = proceso; // null => cierre_caso
  nuevoAsunto.value = '';
  nuevoCuerpo.value = '';
  dialogoNuevo.value?.open?.();
};

const tituloNuevo = computed(() =>
  nuevoProceso.value
    ? t('TICKETS.CORREOS.NUEVA_PARA_PROCESO', {
        proceso: nuevoProceso.value.nombre,
      })
    : t('TICKETS.CORREOS.NUEVA_CIERRE_CASO')
);

const crearPlantilla = () =>
  conAviso(async () => {
    await store.dispatch('helic3Correos/crearPlantilla', {
      disparador: nuevoProceso.value ? 'proceso_garantia' : 'cierre_caso',
      proceso_garantia_id: nuevoProceso.value?.id,
      asunto: nuevoAsunto.value,
      cuerpo: nuevoCuerpo.value,
    });
    useAlert(t('TICKETS.CORREOS.CREADA'));
    dialogoNuevo.value?.close?.();
  });

const comoMarcador = nombre => `{{${nombre}}}`;
const copiar = async nombre => {
  await navigator.clipboard.writeText(comoMarcador(nombre));
  useAlert(t('TICKETS.FORMATOS.MARCADORES.COPIADO'));
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <PlantillaCorreoCard
      v-for="plantilla in plantillas"
      :key="plantilla.id"
      :plantilla="plantilla"
      :es-admin="esAdmin"
      @guardar="guardar"
      @alternar-activo="alternarActivo"
      @previsualizar="previsualizar"
      @prueba="enviarPrueba"
    />

    <!-- Procesos sin correo todavia (p.ej. garantia_negada, D2) -->
    <div
      v-if="esAdmin && (procesosSinPlantilla.length || !tieneCierreCaso)"
      class="flex flex-col gap-2 p-4 border border-dashed rounded-lg border-n-weak"
    >
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('TICKETS.CORREOS.SIN_CORREO_TITLE') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <Button
          v-for="proceso in procesosSinPlantilla"
          :key="proceso.id"
          sm
          faded
          :data-testid="`btn-nueva-${proceso.id}`"
          :label="proceso.nombre"
          icon="i-lucide-plus"
          @click="abrirNuevo(proceso)"
        />
        <Button
          v-if="!tieneCierreCaso"
          sm
          faded
          data-testid="btn-nueva-cierre-caso"
          :label="t('TICKETS.CORREOS.CIERRE_CASO')"
          icon="i-lucide-plus"
          @click="abrirNuevo(null)"
        />
      </div>
    </div>

    <div v-if="previa" class="flex flex-col gap-2">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('TICKETS.CORREOS.VISTA_PREVIA') }}
      </h3>
      <p class="mb-0 text-sm font-medium text-n-slate-11">
        {{ previa.asunto }}
      </p>
      <iframe
        :srcdoc="previa.cuerpo_html"
        data-testid="iframe-previa"
        class="w-full h-[400px] border border-n-weak rounded"
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
      :title="tituloNuevo"
      :confirm-button-label="t('TICKETS.CORREOS.CREAR')"
      :disable-confirm-button="!nuevoAsunto.trim() || !nuevoCuerpo.trim()"
      width="2xl"
      @confirm="crearPlantilla"
    >
      <div class="flex flex-col gap-3">
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('TICKETS.CORREOS.ASUNTO') }}
          </span>
          <input
            v-model="nuevoAsunto"
            data-testid="input-nuevo-asunto"
            class="p-2 border rounded border-n-weak bg-n-alpha-black1"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium text-n-slate-12">
            {{ t('TICKETS.CORREOS.CUERPO') }}
          </span>
          <textarea
            v-model="nuevoCuerpo"
            rows="6"
            data-testid="input-nuevo-cuerpo"
            class="p-2 border rounded resize-y border-n-weak bg-n-alpha-black1"
          />
        </label>
      </div>
    </Dialog>
  </div>
</template>
