<script setup>
import { computed } from 'vue';

// Combo de barras + linea (mockup v12, "Recuento vs. ratio"): @chatwoot/viz
// no trae un tipo de grafica combinada (solo Bar/Donut/Heatmap/Line/
// Percentage/Sankey), asi que se arma a mano con SVG, igual que el propio
// mockup (su funcion comboChart tambien es SVG plano, sin libreria).
const props = defineProps({
  categories: { type: Array, required: true },
  barData: { type: Array, required: true },
  barLabel: { type: String, required: true },
  lineData: { type: Array, required: true },
  lineLabel: { type: String, required: true },
  ariaLabel: { type: String, required: true },
  height: { type: Number, default: 260 },
});

const WIDTH = 600;
const PAD_LEFT = 32;
const PAD_RIGHT = 36;
const PAD_TOP = 16;
const PAD_BOTTOM = 28;
const GRID_STEPS = 4;

const plotWidth = WIDTH - PAD_LEFT - PAD_RIGHT;
const plotHeight = computed(() => props.height - PAD_TOP - PAD_BOTTOM);

const cantidadCategorias = computed(() => props.categories.length || 1);
const maxBarra = computed(() =>
  Math.max(1, ...props.barData.map(valor => valor || 0))
);
const maxLinea = computed(() =>
  Math.max(1, ...props.lineData.map(valor => valor || 0))
);

const coordenadaX = indice =>
  PAD_LEFT + (indice + 0.5) * (plotWidth / cantidadCategorias.value);
const coordenadaYBarra = valor =>
  PAD_TOP + plotHeight.value - (valor / maxBarra.value) * plotHeight.value;
const coordenadaYLinea = valor =>
  PAD_TOP + plotHeight.value - (valor / maxLinea.value) * plotHeight.value;

const anchoBarra = computed(() =>
  Math.min(22, (plotWidth / cantidadCategorias.value) * 0.6)
);

const barras = computed(() =>
  props.barData.map((valor, indice) => {
    const y = coordenadaYBarra(valor || 0);
    return {
      x: coordenadaX(indice) - anchoBarra.value / 2,
      y,
      ancho: anchoBarra.value,
      alto: PAD_TOP + plotHeight.value - y,
      valor,
      etiqueta: props.categories[indice],
    };
  })
);

const puntosLinea = computed(() =>
  props.lineData.map((valor, indice) => ({
    x: coordenadaX(indice),
    y: coordenadaYLinea(valor || 0),
    valor,
    etiqueta: props.categories[indice],
  }))
);

const trazoLinea = computed(() =>
  puntosLinea.value
    .map((punto, indice) => `${indice ? 'L' : 'M'}${punto.x} ${punto.y}`)
    .join(' ')
);

const lineasGuia = computed(() =>
  Array.from({ length: GRID_STEPS + 1 }, (_, indice) => {
    const fraccion = indice / GRID_STEPS;
    return {
      y: PAD_TOP + plotHeight.value - fraccion * plotHeight.value,
      izquierda: Math.round(fraccion * maxBarra.value),
      derecha: Math.round(fraccion * maxLinea.value),
    };
  })
);

const mostrarEtiquetaX = indice =>
  cantidadCategorias.value <= 8 || indice % 2 === 0;
</script>

<template>
  <div>
    <svg
      :viewBox="`0 0 ${WIDTH} ${height}`"
      role="img"
      :aria-label="ariaLabel"
      class="w-full h-auto"
    >
      <g v-for="(linea, indice) in lineasGuia" :key="indice">
        <line
          :x1="PAD_LEFT"
          :x2="WIDTH - PAD_RIGHT"
          :y1="linea.y"
          :y2="linea.y"
          class="stroke-n-weak"
        />
        <text
          :x="PAD_LEFT - 6"
          :y="linea.y + 3"
          text-anchor="end"
          class="fill-n-slate-10 text-[9px]"
        >
          {{ linea.izquierda }}
        </text>
        <text
          :x="WIDTH - PAD_RIGHT + 6"
          :y="linea.y + 3"
          class="fill-n-slate-10 text-[9px]"
        >
          {{ linea.derecha }}%
        </text>
      </g>
      <g v-for="(barra, indice) in barras" :key="`barra-${indice}`">
        <rect
          :x="barra.x"
          :y="barra.y"
          :width="barra.ancho"
          :height="barra.alto"
          rx="2"
          class="fill-n-blue-9"
        >
          <title>{{ barra.etiqueta }}: {{ barra.valor }}</title>
        </rect>
        <text
          v-if="mostrarEtiquetaX(indice)"
          :x="coordenadaX(indice)"
          :y="height - 10"
          text-anchor="middle"
          class="fill-n-slate-10 text-[9px]"
        >
          {{ barra.etiqueta }}
        </text>
      </g>
      <path
        :d="trazoLinea"
        fill="none"
        class="stroke-n-teal-9"
        stroke-width="2"
      />
      <circle
        v-for="(punto, indice) in puntosLinea"
        :key="`punto-${indice}`"
        :cx="punto.x"
        :cy="punto.y"
        r="3"
        class="fill-n-teal-9"
      >
        <title>{{ punto.etiqueta }}: {{ punto.valor }}%</title>
      </circle>
    </svg>
    <div
      class="flex flex-wrap justify-center gap-4 mt-2 text-xs text-n-slate-11"
    >
      <span class="inline-flex items-center gap-1.5">
        <span class="w-2 h-2 rounded-sm bg-n-blue-9" />
        {{ barLabel }}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="w-3 h-0.5 bg-n-teal-9" />
        {{ lineLabel }}
      </span>
    </div>
  </div>
</template>
