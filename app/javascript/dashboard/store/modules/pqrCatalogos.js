import types from '../mutation-types';
import PqrCatalogosAPI from '../../api/pqrCatalogos';

// Store de administracion de catalogos y parametros (ADM-01). Cada catalogo se
// guarda por tipo; los parametros aparte. Tras una escritura se recarga el
// catalogo afectado para reflejar el estado real del servidor.
export const state = {
  catalogos: {},
  parametros: [],
  uiFlags: {
    isFetching: false,
    isSaving: false,
  },
};

export const getters = {
  getCatalogo: _state => tipo => _state.catalogos[tipo] || [],
  getParametros(_state) {
    return _state.parametros;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  fetchCatalogo: async ({ commit }, tipo) => {
    commit(types.SET_PQR_ADMIN_UI_FLAG, { isFetching: true });
    try {
      const { data } = await PqrCatalogosAPI.listCatalogo(tipo);
      commit(types.SET_PQR_CATALOGO, { tipo, registros: data });
    } finally {
      commit(types.SET_PQR_ADMIN_UI_FLAG, { isFetching: false });
    }
  },

  createCatalogo: async ({ commit, dispatch }, { tipo, data }) => {
    commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: true });
    try {
      await PqrCatalogosAPI.createCatalogo(tipo, data);
      await dispatch('fetchCatalogo', tipo);
    } finally {
      commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: false });
    }
  },

  updateCatalogo: async ({ commit, dispatch }, { tipo, id, data }) => {
    commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: true });
    try {
      await PqrCatalogosAPI.updateCatalogo(tipo, id, data);
      await dispatch('fetchCatalogo', tipo);
    } finally {
      commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: false });
    }
  },

  deleteCatalogo: async ({ commit, dispatch }, { tipo, id }) => {
    commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: true });
    try {
      await PqrCatalogosAPI.deleteCatalogo(tipo, id);
      await dispatch('fetchCatalogo', tipo);
    } finally {
      commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: false });
    }
  },

  fetchParametros: async ({ commit }) => {
    commit(types.SET_PQR_ADMIN_UI_FLAG, { isFetching: true });
    try {
      const { data } = await PqrCatalogosAPI.listParametros();
      commit(types.SET_PQR_PARAMETROS, data);
    } finally {
      commit(types.SET_PQR_ADMIN_UI_FLAG, { isFetching: false });
    }
  },

  updateParametro: async ({ commit, dispatch }, { id, data }) => {
    commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: true });
    try {
      await PqrCatalogosAPI.updateParametro(id, data);
      await dispatch('fetchParametros');
    } finally {
      commit(types.SET_PQR_ADMIN_UI_FLAG, { isSaving: false });
    }
  },
};

export const mutations = {
  [types.SET_PQR_ADMIN_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_PQR_CATALOGO](_state, { tipo, registros }) {
    _state.catalogos = { ..._state.catalogos, [tipo]: registros };
  },
  [types.SET_PQR_PARAMETROS](_state, parametros) {
    _state.parametros = parametros;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
