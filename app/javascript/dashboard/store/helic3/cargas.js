import { defineStore } from 'pinia';
import CargasAPI from 'dashboard/api/helic3/cargas';

// IND-03 (parcial): store de "Carga de Datos". Pinia, mismo patron de
// store/helic3/indicadores.js.
export const useCargasStore = defineStore('helic3Cargas', {
  state: () => ({
    cargas: [],
    isFetching: false,
    isSubiendo: false,
  }),

  getters: {
    getCargas: state => state.cargas,
    getUIFlags: state => ({
      isFetching: state.isFetching,
      isSubiendo: state.isSubiendo,
    }),
  },

  actions: {
    async fetchCargas() {
      this.isFetching = true;
      try {
        const response = await CargasAPI.get();
        this.cargas = response.data;
      } finally {
        this.isFetching = false;
      }
    },

    async subirArchivo(payload) {
      this.isSubiendo = true;
      try {
        const response = await CargasAPI.subir(payload);
        this.cargas = [response.data, ...this.cargas];
        return response.data;
      } finally {
        this.isSubiendo = false;
      }
    },

    // El backend rechaza (422) borrar una carga que ya tiene facturas
    // insertadas -- son datos reales, no se van solo porque se limpie el
    // historial. El error se deja pasar tal cual para que la pantalla lo
    // muestre.
    async eliminarCarga(id) {
      await CargasAPI.delete(id);
      this.cargas = this.cargas.filter(carga => carga.id !== id);
    },
  },
});
