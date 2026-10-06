import { defineStore } from 'pinia';
import IndicadoresAPI from 'dashboard/api/helic3/indicadores';

// IND-01: store de la seccion Indicadores. Pinia (mismo patron de
// store/helic3/agentesIa.js), sin el boilerplate de mutation-types de Vuex.
export const useIndicadoresStore = defineStore('helic3Indicadores', {
  state: () => ({
    garantias: null,
    uiFlags: {
      isFetchingGarantias: false,
    },
  }),

  getters: {
    getGarantias: state => state.garantias,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async fetchGarantias(filtros = {}) {
      this.uiFlags.isFetchingGarantias = true;
      try {
        const response = await IndicadoresAPI.garantias(filtros);
        this.garantias = response.data;
      } finally {
        this.uiFlags.isFetchingGarantias = false;
      }
    },
  },
});
