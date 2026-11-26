<script setup>
// GAR-09: aviso de vigencia de garantía en "Datos del caso". Recibe
// expediente.vigencia_garantia (lo calcula el backend) y solo lo pinta. Si llega
// null (expediente que no es de garantía o sin el parámetro), no pinta nada.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { fechaDMY } from 'dashboard/helper/helic3/fecha';

const props = defineProps({
  vigencia: { type: Object, default: null },
});

const { t } = useI18n();

const P = 'TICKETS.DATA.VIGENCIA';

// Color (tokens n- del tema, para que funcione en modo oscuro) y claves por estado.
const ESTILOS = {
  dentro: {
    clases: 'bg-n-teal-3 border-n-teal-4 text-n-teal-11',
    titleKey: `${P}.DENTRO_TITLE`,
    textKey: `${P}.DENTRO_TEXT`,
  },
  fuera: {
    clases: 'bg-n-ruby-3 border-n-ruby-4 text-n-ruby-11',
    titleKey: `${P}.FUERA_TITLE`,
    textKey: `${P}.FUERA_TEXT`,
  },
  sin_fecha_compra: {
    clases: 'bg-n-amber-3 border-n-amber-4 text-n-amber-11',
    titleKey: `${P}.SIN_FECHA_TITLE`,
    textKey: `${P}.SIN_FECHA_TEXT`,
  },
};

const estilo = computed(() => ESTILOS[props.vigencia?.estado] || null);

// {amparo}: en años si es múltiplo de 12 (12 -> "1 año"); si no, en meses.
const amparoTexto = computed(() => {
  const meses = props.vigencia?.amparo_meses;
  if (!meses) return '';
  return meses % 12 === 0 ? t(`${P}.YEARS`, meses / 12) : t(`${P}.MONTHS`, meses);
});

// {antiguedad}: años y meses ("2 años y 2 meses", "9 meses", "menos de 1 mes").
const antiguedadTexto = computed(() => {
  const meses = props.vigencia?.antiguedad_meses;
  if (meses == null) return '';
  if (meses < 1) return t(`${P}.LESS_THAN_MONTH`);
  const anios = Math.floor(meses / 12);
  const resto = meses % 12;
  if (anios && resto) {
    return t(`${P}.YEARS_AND_MONTHS`, {
      years: t(`${P}.YEARS`, anios),
      months: t(`${P}.MONTHS`, resto),
    });
  }
  return anios ? t(`${P}.YEARS`, anios) : t(`${P}.MONTHS`, resto);
});

const texto = computed(() =>
  estilo.value
    ? t(estilo.value.textKey, {
        fecha: fechaDMY(props.vigencia.fecha_radicacion),
        antiguedad: antiguedadTexto.value,
        amparo: amparoTexto.value,
        hasta: fechaDMY(props.vigencia.amparo_hasta),
      })
    : ''
);
</script>

<template>
  <div
    v-if="estilo"
    data-testid="aviso-vigencia"
    class="p-3 mb-3 text-sm border rounded-lg"
    :class="estilo.clases"
  >
    <p class="font-medium">{{ t(estilo.titleKey) }}</p>
    <p class="mt-0.5">{{ texto }}</p>
  </div>
</template>
