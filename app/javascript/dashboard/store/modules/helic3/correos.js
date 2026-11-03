import types from '../../mutation-types';
import Helic3CorreosAPI from '../../../api/helic3/correos';

// COR-04: store de la pestana Correos. Tras crear/actualizar una plantilla
// recarga la lista para reflejar el estado real del servidor (mismo patron
// que helic3Formatos). vistaPrevia y enviarPrueba no tocan el state: el panel
// solo necesita la respuesta puntual, no guardarla.
export const state = {
  plantillas: [],
  uiFlags: {
    isFetching: false,
    isSaving: false,
  },
};

export const getters = {
  getPlantillas(_state) {
    return _state.plantillas;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  fetchPlantillas: async ({ commit }) => {
    commit(types.SET_HELIC3_PLANTILLAS_CORREO_UI_FLAG, { isFetching: true });
    try {
      const { data } = await Helic3CorreosAPI.listPlantillas();
      commit(types.SET_HELIC3_PLANTILLAS_CORREO, data);
    } finally {
      commit(types.SET_HELIC3_PLANTILLAS_CORREO_UI_FLAG, { isFetching: false });
    }
  },
  crearPlantilla: async ({ commit, dispatch }, payload) => {
    commit(types.SET_HELIC3_PLANTILLAS_CORREO_UI_FLAG, { isSaving: true });
    try {
      await Helic3CorreosAPI.crearPlantilla(payload);
      await dispatch('fetchPlantillas');
    } finally {
      commit(types.SET_HELIC3_PLANTILLAS_CORREO_UI_FLAG, { isSaving: false });
    }
  },
  actualizarPlantilla: async ({ commit, dispatch }, { id, data }) => {
    commit(types.SET_HELIC3_PLANTILLAS_CORREO_UI_FLAG, { isSaving: true });
    try {
      await Helic3CorreosAPI.actualizarPlantilla(id, data);
      await dispatch('fetchPlantillas');
    } finally {
      commit(types.SET_HELIC3_PLANTILLAS_CORREO_UI_FLAG, { isSaving: false });
    }
  },
  // devuelve {asunto, cuerpo_html}; el panel la pinta en un iframe con srcdoc.
  vistaPrevia: (_store, id) =>
    Helic3CorreosAPI.vistaPrevia(id).then(respuesta => respuesta.data),
  enviarPrueba: (_store, id) => Helic3CorreosAPI.enviarPrueba(id),
};

export const mutations = {
  [types.SET_HELIC3_PLANTILLAS_CORREO]: (_state, data) => {
    _state.plantillas = data;
  },
  [types.SET_HELIC3_PLANTILLAS_CORREO_UI_FLAG]: (_state, flag) => {
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
