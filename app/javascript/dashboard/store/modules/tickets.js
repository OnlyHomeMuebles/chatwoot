import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import TicketsAPI from '../../api/tickets';

export const state = {
  records: [],
  catalogos: { tipos: [], motivos_pqr: [], etapas_pqr: [], resultados: [] },
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getTickets(_state) {
    return [..._state.records].sort((t1, t2) => t2.id - t1.id);
  },
  getCatalogos(_state) {
    return _state.catalogos;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_TICKET_UI_FLAG, { isFetching: true });
    try {
      const response = await TicketsAPI.get();
      commit(types.SET_TICKETS, response.data);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isFetching: false });
    }
  },
  // el detalle trae semaforo y dias_habiles_restantes, que el listado omite (se
  // derivan y encarecerian cada fila). El panel lo pide por los pocos tickets de
  // la conversacion para poder pintar el chip del semaforo.
  show: async ({ commit }, id) => {
    try {
      const response = await TicketsAPI.show(id);
      commit(types.EDIT_TICKET, response.data);
    } catch (error) {
      // Ignore error: el ticket se sigue mostrando con lo que trajo el listado
    }
  },
  // los catalogos casi no cambian: se traen una vez por sesion y se cachean.
  // No se traga el error: si falla, los selectores quedan vacios y el operador
  // podria crear un expediente sin clasificar sin enterarse. Se propaga para que
  // el dialogo avise (igual que create), en vez de degradar en silencio.
  getCatalogos: async ({ commit, state: currentState }) => {
    if (currentState.catalogos.tipos.length) return;
    const response = await TicketsAPI.catalogos();
    commit(types.SET_TICKET_CATALOGOS, response.data);
  },
  create: async ({ commit }, ticketObj) => {
    commit(types.SET_TICKET_UI_FLAG, { isCreating: true });
    try {
      const response = await TicketsAPI.create(ticketObj);
      commit(types.ADD_TICKET, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isCreating: false });
    }
  },
  // update/assign have no catch on purpose: the original axios error is
  // rethrown so callers can inspect the response status (permissions)
  update: async ({ commit }, { id, ...updateObj }) => {
    commit(types.SET_TICKET_UI_FLAG, { isUpdating: true });
    try {
      const response = await TicketsAPI.update(id, { ticket: updateObj });
      commit(types.EDIT_TICKET, response.data);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isUpdating: false });
    }
  },
  assign: async ({ commit }, { id, assigneeId }) => {
    commit(types.SET_TICKET_UI_FLAG, { isUpdating: true });
    try {
      const response = await TicketsAPI.assign(id, assigneeId);
      commit(types.EDIT_TICKET, response.data);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isUpdating: false });
    }
  },
  // resolver (RES-01): registra el resultado por el endpoint propio. Sin catch a
  // proposito, igual que update: se relanza el error de axios para que el panel
  // pueda revertir el selector si el servidor rechaza (p. ej. sin permiso).
  resolver: async ({ commit }, { id, resultadoId }) => {
    commit(types.SET_TICKET_UI_FLAG, { isUpdating: true });
    try {
      const response = await TicketsAPI.resolver(id, resultadoId);
      commit(types.EDIT_TICKET, response.data);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isUpdating: false });
    }
  },
  // registrarDatos (DAT-01): el operador corrige la ficha; el campo queda con
  // fuente humano. Sin catch, igual que resolver: se relanza para que el panel
  // revierta el input si el servidor rechaza.
  registrarDatos: async ({ commit }, { id, datos }) => {
    commit(types.SET_TICKET_UI_FLAG, { isUpdating: true });
    try {
      const response = await TicketsAPI.registrarDatos(id, datos);
      commit(types.EDIT_TICKET, response.data);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isUpdating: false });
    }
  },
  // avanzarGarantia (GAR-03): mueve un producto de proceso; el backend cierra el
  // radicado si con eso todos resolvieron. Sin catch, se relanza para revertir.
  avanzarGarantia: async ({ commit }, { garantiaId, itemId, procesoId }) => {
    commit(types.SET_TICKET_UI_FLAG, { isUpdating: true });
    try {
      const response = await TicketsAPI.avanzarGarantia(garantiaId, itemId, procesoId);
      commit(types.EDIT_TICKET, response.data);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_TICKET_UI_FLAG, { isDeleting: true });
    // no catch: rethrow the original axios error so callers can
    // inspect the response status (e.g. permission denied)
    try {
      await TicketsAPI.delete(id);
      commit(types.DELETE_TICKET, id);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_TICKET_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.ADD_TICKET]: MutationHelpers.create,
  [types.SET_TICKETS]: MutationHelpers.set,
  [types.EDIT_TICKET]: MutationHelpers.update,
  [types.DELETE_TICKET]: MutationHelpers.destroy,

  [types.SET_TICKET_CATALOGOS](_state, data) {
    _state.catalogos = data;
  },
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
