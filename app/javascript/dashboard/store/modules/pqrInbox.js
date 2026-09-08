import types from '../mutation-types';
import PqrInboxAPI from '../../api/pqr';

// Store propio de la bandeja de PQR (BAN-01). NO reutiliza el del panel de
// conversacion (tickets.js): abrir la bandeja no debe alterar lo que el panel ya
// tenia cargado. Lleva su propia paginacion y sus propios filtros.
export const state = {
  records: [],
  meta: { count: 0, currentPage: 1 },
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getRecords(_state) {
    return _state.records;
  },
  getMeta(_state) {
    return _state.meta;
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
      });
    } finally {
      commit(types.SET_PQR_INBOX_UI_FLAG, { isFetching: false });
    }
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
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
