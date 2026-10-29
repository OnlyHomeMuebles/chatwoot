<script setup>
import { computed } from 'vue';

// Paridad con el Dash CX ("Garantias/Devoluciones por motivo", "Detalle
// tipificado"): grafico de barras agrupadas, una serie coloreada por motivo/
// detalle, agrupadas por trimestre. @chatwoot/viz no trae este tipo (solo
// Bar/Donut/Heatmap/Line/Percentage/Sankey de una sola serie), asi que se
// arma a mano con SVG, mismo criterio que ComboBarLineChart.vue. Clickear
// una categoria (un trimestre) la emite para que el padre la despliegue por
// mes -- igual que el Dash CX, el click es sobre la categoria, no sobre una
// barra de un motivo en particular.
const props = defineProps({
  categories: { type: Array, required: true },
  series: { type: Array, required: true }, // [{ nombre, valores: number[] }]
  ariaLabel: { type: String, required: true },
  height: { type: Number, default: 240 },
  selectedCategory: { type: String, default: null },
});

const emit = defineEmits(['select-category']);

const PALETA = [
  'fill-n-blue-9',
  'fill-n-teal-9',
  'fill-n-violet-9',
  'fill-n-amber-9',
  'fill-n-ruby-9',
  'fill-n-iris-9',
];
const PALETA_LEYENDA = [
  'bg-n-blue-9',
  'bg-n-teal-9',
  'bg-n-violet-9',
  'bg-n-amber-9',
  'bg-n-ruby-9',
  'bg-n-iris-9',
];

const WIDTH = 600;
const PAD_LEFT = 34;
const PAD_RIGHT = 12;
const PAD_TOP = 16;
const PAD_BOTTOM = 28;
const GRID_STEPS = 4;

const plotWidth = WIDTH - PAD_LEFT - PAD_RIGHT;
const plotHeight = computed(() => props.height - PAD_TOP - PAD_BOTTOM);
const cantidadCategorias = computed(() => props.categories.length || 1);

const maxValor = computed(() =>
  Math.max(1, ...props.series.flatMap(serie => serie.valores.map(v => v || 0)))
);

const anchoGrupo = computed(() => plotWidth / cantidadCategorias.value);
const anchoBarra = computed(() =>
  Math.min(16, (anchoGrupo.value * 0.7) / (props.series.length || 1))
);

const coordenadaY = valor =>
  PAD_TOP + plotHeight.value - (valor / maxValor.value) * plotHeight.value;

const gruposDeBarras = computed(() =>
  props.categories.map((categoria, indiceCategoria) => {
    const inicioGrupo =
      PAD_LEFT +
      indiceCategoria * anchoGrupo.value +
      (anchoGrupo.value - anchoBarra.value * props.series.length) / 2;
    const barras = props.series.map((serie, indiceSerie) => {
      const valor = serie.valores[indiceCategoria] || 0;
      const y = coordenadaY(valor);
      return {
        x: inicioGrupo + indiceSerie * anchoBarra.value,
        y,
        alto: PAD_TOP + plotHeight.value - y,
        valor,
        color: PALETA[indiceSerie % PALETA.length],
        nombre: serie.nombre,
      };
    });
    return {
      categoria,
      barras,
      xCentro: PAD_LEFT + (indiceCategoria + 0.5) * anchoGrupo.value,
      xInicio: PAD_LEFT + indiceCategoria * anchoGrupo.value,
    };
  })
);

const lineasGuia = computed(() =>
  Array.from({ length: GRID_STEPS + 1 }, (_, indice) => {
    const fraccion = indice / GRID_STEPS;
    return {
      y: PAD_TOP + plotHeight.value - fraccion * plotHeight.value,
      valor: Math.round(fraccion * maxValor.value),
    };
  })
);
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
          {{ linea.valor }}
        </text>
      </g>
      <g
        v-for="grupo in gruposDeBarras"
        :key="grupo.categoria"
        class="cursor-pointer"
        role="button"
        :tabindex="0"
        @click="emit('select-category', grupo.categoria)"
        @keydown.enter="emit('select-category', grupo.categoria)"
      >
        <rect
          :x="grupo.xInicio"
          :y="PAD_TOP"
          :width="anchoGrupo"
          :height="plotHeight"
          :class="
            selectedCategory === grupo.categoria
              ? 'fill-n-blue-3/40'
              : 'fill-transparent'
          "
        />
        <rect
          v-for="(barra, indice) in grupo.barras"
          :key="`${grupo.categoria}-${indice}`"
          :x="barra.x"
          :y="barra.y"
          :width="anchoBarra"
          :height="barra.alto"
          rx="1.5"
          :class="barra.color"
        >
          <title>
            {{ grupo.categoria }} · {{ barra.nombre }}: {{ barra.valor }}
          </title>
        </rect>
        <text
          :x="grupo.xCentro"
          :y="height - 10"
          text-anchor="middle"
          class="fill-n-slate-10 text-[9px]"
          :class="{
            'font-medium fill-n-blue-11': selectedCategory === grupo.categoria,
          }"
        >
          {{ grupo.categoria }}
        </text>
      </g>
    </svg>
    <div
      class="flex flex-wrap justify-center gap-x-4 gap-y-1 mt-2 text-xs text-n-slate-11"
    >
      <span
        v-for="(serie, indice) in series"
        :key="serie.nombre"
        class="inline-flex items-center gap-1.5"
      >
        <span
          class="w-2 h-2 rounded-sm"
          :class="PALETA_LEYENDA[indice % PALETA_LEYENDA.length]"
        />
        {{ serie.nombre }}
      </span>
    </div>
  </div>
</template>
