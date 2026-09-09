/* global axios */
import ApiClient from './ApiClient';

class TicketsAPI extends ApiClient {
  constructor() {
    super('helic3/tickets', { accountScoped: true });
  }

  assign(ticketId, assigneeId) {
    return axios.post(`${this.url}/${ticketId}/assign`, {
      assignee_id: assigneeId,
    });
  }

  // Catalogos de clasificacion (API-01) para poblar los selectores del panel.
  // Cuelgan del mismo namespace helic3, al lado de tickets.
  catalogos() {
    return axios.get(this.url.replace(/tickets$/, 'catalogos'));
  }
}

export default new TicketsAPI();
