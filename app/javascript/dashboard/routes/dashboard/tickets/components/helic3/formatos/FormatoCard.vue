<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// FMT-03: tarjeta de un formato. Es de PRESENTACION: no habla con el store, solo
// emite eventos (subir/activar/descartar/descargar/previsualizar) al panel.
const props = defineProps({
  formato: { type: Object, required: true },
  esAdmin: { type: Boolean, default: false },
  desconocidos: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'subir',
  'activar',
  'descartar',
  'descargar',
  'previsualizar',
  'desactivar',
  'reactivar',
]);
const { t } = useI18n();

const archivoRef = ref(null);
const dialogoActivar = ref(null);
const dialogoDesactivar = ref(null);

const activa = computed(() =>
  props.formato.versiones.find(
    version => version.id === props.formato.activa_id
  )
);
const borrador = computed(() =>
  props.formato.versiones.find(version => version.estado === 'borrador')
);

const abrirSelector = () => archivoRef.value.click();

const alElegirArchivo = event => {
  const [archivo] = event.target.files;
  event.target.value = '';
  if (archivo) emit('subir', { formato: props.formato, archivo });
};

const confirmarActivar = () => {
  if (borrador.value) emit('activar', borrador.value.id);
  dialogoActivar.value?.close();
};

const confirmarDesactivar = () => {
  emit('desactivar', props.formato.id);
  dialogoDesactivar.value?.close();
};
</script>

<template>
  <div
    class="flex flex-col gap-2 p-4 border border-n-weak rounded-lg"
    :data-testid="`card-${formato.codigo}`"
  >
    <h3 class="flex items-center gap-2 text-base font-medium text-n-slate-12">
      {{ formato.nombre }}
      <span
        v-if="!formato.activo"
        data-testid="badge-desactivado"
        class="px-1.5 py-0.5 text-xs rounded bg-n-slate-3 text-n-slate-11"
      >
        {{ t('TICKETS.FORMATOS.DESACTIVADO_BADGE') }}
      </span>
    </h3>

    <p v-if="activa" class="text-sm text-n-slate-11">
      {{ t('TICKETS.FORMATOS.VERSION_ACTIVA', { version: activa.version }) }}
    </p>
    <p v-else data-testid="sin-plantilla" class="text-sm text-n-ruby-11">
      {{ t('TICKETS.FORMATOS.SIN_PLANTILLA') }}
    </p>

    <ul
      v-if="desconocidos.length"
      data-testid="desconocidos"
      class="text-sm text-n-ruby-11"
    >
      <li>{{ t('TICKETS.FORMATOS.DESCONOCIDOS') }}</li>
      <li v-for="marcador in desconocidos" :key="marcador">{{ marcador }}</li>
    </ul>

    <div class="flex flex-wrap gap-2">
      <Button
        v-if="activa"
        sm
        faded
        data-testid="btn-previa"
        :label="t('TICKETS.FORMATOS.VISTA_PREVIA')"
        @click="emit('previsualizar', activa.id)"
      />
      <Button
        v-if="activa"
        sm
        faded
        data-testid="btn-descargar"
        :label="t('TICKETS.FORMATOS.DESCARGAR')"
        @click="emit('descargar', activa.id)"
      />
      <template v-if="esAdmin">
        <Button
          sm
          data-testid="btn-subir"
          :label="t('TICKETS.FORMATOS.SUBIR')"
          @click="abrirSelector"
        />
        <Button
          v-if="borrador"
          sm
          ruby
          data-testid="btn-activar"
          :label="t('TICKETS.FORMATOS.ACTIVAR')"
          @click="dialogoActivar.open()"
        />
        <Button
          v-if="borrador"
          sm
          ghost
          data-testid="btn-descartar"
          :label="t('TICKETS.FORMATOS.DESCARTAR')"
          @click="emit('descartar', borrador.id)"
        />
        <Button
          v-if="formato.activo"
          sm
          ghost
          data-testid="btn-desactivar"
          :label="t('TICKETS.FORMATOS.DESACTIVAR')"
          @click="dialogoDesactivar.open()"
        />
        <Button
          v-else
          sm
          faded
          data-testid="btn-reactivar"
          :label="t('TICKETS.FORMATOS.REACTIVAR')"
          @click="emit('reactivar', formato.id)"
        />
      </template>
    </div>

    <input
      ref="archivoRef"
      type="file"
      accept=".docx"
      class="hidden"
      data-testid="input-archivo"
      @change="alElegirArchivo"
    />

    <Dialog
      ref="dialogoActivar"
      type="alert"
      :title="t('TICKETS.FORMATOS.ACTIVAR')"
      :description="t('TICKETS.FORMATOS.ACTIVAR_CONFIRMACION')"
      :confirm-button-label="t('TICKETS.FORMATOS.ACTIVAR')"
      @confirm="confirmarActivar"
    />

    <Dialog
      ref="dialogoDesactivar"
      type="alert"
      :title="t('TICKETS.FORMATOS.DESACTIVAR')"
      :description="t('TICKETS.FORMATOS.DESACTIVAR_CONFIRMACION')"
      :confirm-button-label="t('TICKETS.FORMATOS.DESACTIVAR')"
      @confirm="confirmarDesactivar"
    />
  </div>
</template>
