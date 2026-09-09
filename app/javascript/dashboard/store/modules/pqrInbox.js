import types from '../mutation-types';
import PqrInboxAPI from '../../api/pqr';
import TicketsAPI from '../../api/tickets';

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
  current: null,
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
  },
};

export const getters = {
  getRecords(_state) {
    return _state.records;
  },
  getMeta(_state) {
    return _state.meta;
  },
  getCurrent(_state) {
    return _state.current;
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

  // Detalle de un expediente (DET-01). Se guarda aparte de la lista para que la
  // pantalla de detalle no dependa de que el expediente este en la pagina actual.
  fetchOne: async ({ commit }, id) => {
    commit(types.SET_PQR_INBOX_UI_FLAG, { isFetchingItem: true });
    commit(types.SET_PQR_CURRENT, null);
    try {
      // Reusa el show de tickets (helic3/tickets/:id) — importar api/tickets.js no
      // es editar el archivo de Samuel; asi el detalle no arma la URL a mano.
      const { data } = await TicketsAPI.show(id);
      commit(types.SET_PQR_CURRENT, data);
    } finally {
      commit(types.SET_PQR_INBOX_UI_FLAG, { isFetchingItem: false });
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
  [types.SET_PQR_CURRENT](_state, record) {
    _state.current = record;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
