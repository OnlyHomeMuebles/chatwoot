import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import TicketsAPI from '../../api/tickets';

export const state = {
  records: [],
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
  update: async ({ commit }, { id, ...updateObj }) => {
    commit(types.SET_TICKET_UI_FLAG, { isUpdating: true });
    try {
      const response = await TicketsAPI.update(id, { ticket: updateObj });
      commit(types.EDIT_TICKET, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_TICKET_UI_FLAG, { isUpdating: false });
    }
  },
  assign: async ({ commit }, { id, assigneeId }) => {
    commit(types.SET_TICKET_UI_FLAG, { isUpdating: true });
    try {
      const response = await TicketsAPI.assign(id, assigneeId);
      commit(types.EDIT_TICKET, response.data);
    } catch (error) {
      throw new Error(error);
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
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
