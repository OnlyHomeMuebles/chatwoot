import { defineStore } from 'pinia';
import IndicadoresAPI from 'dashboard/api/helic3/indicadores';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';

// IND-01: store de la seccion Indicadores. Pinia (mismo patron de
// store/helic3/agentesIa.js), sin el boilerplate de mutation-types de Vuex.
//
// N2 (revision de Jhan, PR #113): el debounce del filtro de producto reduce
// peticiones, pero no evita que una respuesta tardia pise una mas nueva. El
// mismo singleton por-modulo que usa conversations/actions.js (fuera del
// store, no dentro de un setup-store) cancela la peticion anterior apenas
// arranca una nueva, asi solo la ultima puede escribir el estado.
const garantiasRequest = useAbortableRequest();

export const useIndicadoresStore = defineStore('helic3Indicadores', {
  state: () => ({
    garantias: null,
  }),

  getters: {
    getGarantias: state => state.garantias,
    // isPending ya solo refleja la peticion vigente (ver "Only the latest run
    // owns the shared state" en useAbortableRequest) -- una respuesta
    // cancelada no apaga el spinner de la que la reemplazo.
    getUIFlags: () => ({
      isFetchingGarantias: garantiasRequest.isPending.value,
    }),
  },

  actions: {
    async fetchGarantias(filtros = {}) {
      await garantiasRequest.run(async signal => {
        const response = await IndicadoresAPI.garantias(filtros, { signal });
        // una respuesta que llega DESPUES de que otra peticion la reemplazo no
        // debe escribir el estado, aunque el mock/navegador no respete el abort.
        if (signal.aborted) return;
        this.garantias = response.data;
      });
    },
  },
});
