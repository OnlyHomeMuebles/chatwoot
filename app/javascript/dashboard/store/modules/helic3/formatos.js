import types from '../../mutation-types';
import Helic3FormatosAPI from '../../../api/helic3/formatos';

// FMT-03: store de la pantalla de formatos. Lee los formatos con su version activa
// y el diccionario de marcadores; tras subir/activar/descartar recarga la lista para
// reflejar el estado real del servidor. subirPlantilla relanza el error para que el
// panel lea el 422 (marcadores desconocidos).
export const state = {
  formatos: [],
  marcadores: {},
  uiFlags: {
    isFetching: false,
    isSaving: false,
  },
};

export const getters = {
  getFormatos(_state) {
    return _state.formatos;
  },
  getMarcadores(_state) {
    return _state.marcadores;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  fetchFormatos: async ({ commit }) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await Helic3FormatosAPI.listFormatos();
      commit(types.SET_HELIC3_FORMATOS, data);
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isFetching: false });
    }
  },
  fetchMarcadores: async ({ commit }) => {
    const { data } = await Helic3FormatosAPI.marcadores();
    commit(types.SET_HELIC3_MARCADORES, data);
  },
  subirPlantilla: async ({ commit, dispatch }, { formatoId, formData }) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      const { data } = await Helic3FormatosAPI.subirPlantilla(
        formatoId,
        formData
      );
      await dispatch('fetchFormatos');
      return data;
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  activar: async ({ commit, dispatch }, plantillaId) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      await Helic3FormatosAPI.activar(plantillaId);
      await dispatch('fetchFormatos');
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  descartar: async ({ commit, dispatch }, plantillaId) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      await Helic3FormatosAPI.descartar(plantillaId);
      await dispatch('fetchFormatos');
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  // FMT-06: crear un formato nuevo. Re-lanza el error (p. ej. 422 por codigo
  // repetido) para que el panel muestre el mensaje del servidor.
  crearFormato: async ({ commit, dispatch }, payload) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      await Helic3FormatosAPI.crearFormato(payload);
      await dispatch('fetchFormatos');
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  // FMT-06: desactivar (activo: false), nunca borrar: no se rompe el historial.
  desactivarFormato: async ({ commit, dispatch }, formatoId) => {
    commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: true });
    try {
      await Helic3FormatosAPI.actualizarFormato(formatoId, { activo: false });
      await dispatch('fetchFormatos');
    } finally {
      commit(types.SET_HELIC3_FORMATOS_UI_FLAG, { isSaving: false });
    }
  },
  // devuelven el blob (el panel arma la URL); el componente NO llama la API directo.
  vistaPrevia: (_store, plantillaId) =>
    Helic3FormatosAPI.vistaPrevia(plantillaId).then(
      respuesta => respuesta.data
    ),
  descargarOriginal: (_store, plantillaId) =>
    Helic3FormatosAPI.descargarOriginal(plantillaId).then(
      respuesta => respuesta.data
    ),
};

export const mutations = {
  [types.SET_HELIC3_FORMATOS]: (_state, data) => {
    _state.formatos = data;
  },
  [types.SET_HELIC3_MARCADORES]: (_state, data) => {
    _state.marcadores = data;
  },
  [types.SET_HELIC3_FORMATOS_UI_FLAG]: (_state, flag) => {
    _state.uiFlags = { ..._state.uiFlags, ...flag };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
