<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// COR-04: tarjeta de una plantilla de correo. Es de PRESENTACION: no habla con
// el store, solo emite eventos (guardar/alternarActivo/previsualizar/prueba)
// al panel. El titulo es el nombre del proceso, o "Cierre de caso" cuando la
// plantilla no cuelga de un proceso (disparador cierre_caso).
const props = defineProps({
  plantilla: { type: Object, required: true },
  esAdmin: { type: Boolean, default: false },
});
const emit = defineEmits([
  'guardar',
  'alternarActivo',
  'previsualizar',
  'prueba',
]);
const { t } = useI18n();

const asunto = ref(props.plantilla.asunto);
const cuerpo = ref(props.plantilla.cuerpo);

// si el panel recarga tras guardar, refleja el valor real del servidor.
watch(
  () => props.plantilla,
  nueva => {
    asunto.value = nueva.asunto;
    cuerpo.value = nueva.cuerpo;
  }
);

const cambio = computed(
  () =>
    asunto.value !== props.plantilla.asunto ||
    cuerpo.value !== props.plantilla.cuerpo
);

const titulo = computed(() =>
  props.plantilla.disparador === 'cierre_caso'
    ? t('TICKETS.CORREOS.CIERRE_CASO')
    : props.plantilla.proceso_nombre
);

const guardar = () => {
  if (!cambio.value) return;
  emit('guardar', {
    id: props.plantilla.id,
    data: { asunto: asunto.value, cuerpo: cuerpo.value },
  });
};
</script>

<template>
  <div
    class="flex flex-col gap-3 p-4 border border-n-weak rounded-lg"
    :class="plantilla.activo ? '' : 'opacity-50'"
    :data-testid="`card-plantilla-${plantilla.id}`"
  >
    <div class="flex items-center gap-2">
      <h3 class="flex-1 mb-0 text-base font-medium text-n-slate-12">
        {{ titulo }}
      </h3>
      <span
        class="px-2 py-0.5 text-xs font-medium rounded-md"
        :class="
          plantilla.activo
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-slate-3 text-n-slate-11'
        "
      >
        {{
          plantilla.activo
            ? t('TICKETS.CORREOS.ACTIVA')
            : t('TICKETS.CORREOS.INACTIVA')
        }}
      </span>
    </div>

    <label class="flex flex-col gap-1 text-sm">
      <span class="font-medium text-n-slate-12">
        {{ t('TICKETS.CORREOS.ASUNTO') }}
      </span>
      <input
        v-model="asunto"
        :disabled="!esAdmin"
        data-testid="input-asunto"
        class="p-2 text-sm border rounded border-n-weak bg-n-alpha-black1"
      />
    </label>

    <label class="flex flex-col gap-1 text-sm">
      <span class="font-medium text-n-slate-12">
        {{ t('TICKETS.CORREOS.CUERPO') }}
      </span>
      <textarea
        v-model="cuerpo"
        :disabled="!esAdmin"
        rows="6"
        data-testid="input-cuerpo"
        class="p-2 text-sm border rounded resize-y border-n-weak bg-n-alpha-black1"
      />
    </label>

    <div class="flex flex-wrap gap-2">
      <Button
        sm
        faded
        data-testid="btn-previa"
        :label="t('TICKETS.CORREOS.VISTA_PREVIA')"
        @click="emit('previsualizar', plantilla.id)"
      />
      <template v-if="esAdmin">
        <Button
          sm
          data-testid="btn-guardar"
          :disabled="!cambio"
          :label="t('TICKETS.CORREOS.GUARDAR')"
          @click="guardar"
        />
        <Button
          sm
          faded
          data-testid="btn-prueba"
          :label="t('TICKETS.CORREOS.ENVIAR_PRUEBA')"
          @click="emit('prueba', plantilla.id)"
        />
        <Button
          sm
          ghost
          data-testid="btn-alternar-activo"
          :label="
            plantilla.activo
              ? t('TICKETS.CORREOS.DESACTIVAR')
              : t('TICKETS.CORREOS.ACTIVAR')
          "
          @click="emit('alternarActivo', plantilla)"
        />
      </template>
    </div>
  </div>
</template>
