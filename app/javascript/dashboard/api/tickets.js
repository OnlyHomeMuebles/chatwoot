/* global axios */
import ApiClient from './ApiClient';

class TicketsAPI extends ApiClient {
  constructor() {
    super('tickets', { accountScoped: true });
  }

  assign(ticketId, assigneeId) {
    return axios.post(`${this.url}/${ticketId}/assign`, {
      assignee_id: assigneeId,
    });
  }
}

export default new TicketsAPI();
