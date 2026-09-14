import types from '../mutation-types';
import PqrInboxAPI from '../../api/pqr';

// Store propio de la bandeja de PQR (BAN-01). NO reutiliza el del panel de
// conversacion (tickets.js): abrir la bandeja no debe alterar lo que el panel ya
// tenia cargado. Lleva su propia paginacion y sus propios filtros.
export const state = {
  records: [],
  meta: {
    count: 0,
    currentPage: 1,
    perPage: 25,
    umbralVerde: null,
    umbralAmarillo: null,
  },
  decisiones: [],
  uiFlags: {
    isFetching: false,
    isFetchingDecisiones: false,
  },
};

export const getters = {
  getRecords(_state) {
    return _state.records;
  },
  getMeta(_state) {
    return _state.meta;
  },
  getDecisiones(_state) {
    return _state.decisiones;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  // sin catch: el error se propaga para que el componente avise; el finally solo
  // baja el flag de carga.
  fetch: async ({ commit }, params = {}) => {
    commit(types.SET_PQR_INBOX_UI_FLAG, { isFetching: true });
    try {
      const { data } = await PqrInboxAPI.list(params);
      commit(types.SET_PQR_INBOX, data.payload);
      commit(types.SET_PQR_INBOX_META, {
        count: data.meta.count,
        currentPage: Number(data.meta.current_page),
        perPage: data.meta.per_page,
        umbralVerde: data.meta.umbral_verde ?? null,
        umbralAmarillo: data.meta.umbral_amarillo ?? null,
      });
    } finally {
      commit(types.SET_PQR_INBOX_UI_FLAG, { isFetching: false });
    }
  },

  // Cola de decisiones (DEC-01).
  fetchDecisiones: async ({ commit }) => {
    commit(types.SET_PQR_INBOX_UI_FLAG, { isFetchingDecisiones: true });
    try {
      const { data } = await PqrInboxAPI.decisiones();
      commit(types.SET_PQR_DECISIONES, data);
    } finally {
      commit(types.SET_PQR_INBOX_UI_FLAG, { isFetchingDecisiones: false });
    }
  },

  // Aprobar aplica el resultado propuesto por la puerta de resolucion (RES-01) y
  // recarga la cola: la fila aprobada sale (ya no tiene propuesta pendiente). Sin
  // catch: el error (p. ej. 401 de un agente) se propaga para que la pantalla avise.
  aprobarDecision: async ({ dispatch }, { ticketId, resultadoId }) => {
    await PqrInboxAPI.aprobar(ticketId, resultadoId);
    await dispatch('fetchDecisiones');
  },
};

export const mutations = {
  [types.SET_PQR_INBOX_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_PQR_INBOX](_state, records) {
    _state.records = records;
  },
  [types.SET_PQR_INBOX_META](_state, meta) {
    _state.meta = meta;
  },
  [types.SET_PQR_DECISIONES](_state, decisiones) {
    _state.decisiones = decisiones;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
