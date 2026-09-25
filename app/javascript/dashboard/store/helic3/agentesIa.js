import { defineStore } from 'pinia';
import AgentesIaAPI from 'dashboard/api/helic3/agentesIa';

// H3A-13/14: store de agentes IA. Pinia (como Captain) para no arrastrar el
// boilerplate de mutation-types. El indice devuelve un array plano (response.data).
export const useAgentesIaStore = defineStore('helic3AgentesIa', {
  state: () => ({
    records: [],
    catalogo: { herramientas: [], reglas_duras: '' },
    uiFlags: {
      isFetching: false,
      isFetchingCatalogo: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    },
  }),

  getters: {
    getAgentes: state => state.records,
    getAgente: state => id => state.records.find(a => a.id === Number(id)),
    getCatalogo: state => state.catalogo,
    getUIFlags: state => state.uiFlags,
    // contadores de la lista (H3A-13): configurados, activos, bandejas cubiertas.
    getStats: state => {
      const activos = state.records.filter(a => a.activo);
      const bandejas = new Set(
        activos.flatMap(a => (a.bandejas || []).map(b => b.inbox_id))
      );
      return {
        total: state.records.length,
        activos: activos.length,
        bandejasCubiertas: bandejas.size,
      };
    },
  },

  actions: {
    async fetch() {
      this.uiFlags.isFetching = true;
      try {
        const response = await AgentesIaAPI.get();
        this.records = response.data;
      } finally {
        this.uiFlags.isFetching = false;
      }
    },
    async fetchCatalogo() {
      this.uiFlags.isFetchingCatalogo = true;
      try {
        const response = await AgentesIaAPI.catalogo();
        this.catalogo = response.data;
      } finally {
        this.uiFlags.isFetchingCatalogo = false;
      }
    },
    async create(payload) {
      this.uiFlags.isCreating = true;
      try {
        const response = await AgentesIaAPI.create({ agente: payload });
        this.records.push(response.data);
        return response.data;
      } finally {
        this.uiFlags.isCreating = false;
      }
    },
    async update(id, payload) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await AgentesIaAPI.update(id, { agente: payload });
        this.reemplazar(response.data);
        return response.data;
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },
    async toggle(id) {
      const response = await AgentesIaAPI.toggle(id);
      this.reemplazar(response.data);
      return response.data;
    },
    async remove(id) {
      this.uiFlags.isDeleting = true;
      try {
        await AgentesIaAPI.delete(id);
        this.records = this.records.filter(a => a.id !== id);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },
    reemplazar(agente) {
      const i = this.records.findIndex(a => a.id === agente.id);
      if (i !== -1) this.records.splice(i, 1, agente);
      else this.records.push(agente);
    },
  },
});
