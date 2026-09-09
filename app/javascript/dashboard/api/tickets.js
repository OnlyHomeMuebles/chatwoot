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

  // Registra el resultado de la PQR (RES-01): la unica puerta para resolver, que
  // detiene el reloj legal. Endpoint propio, no un update de campos sueltos.
  resolver(ticketId, resultadoId) {
    return axios.post(`${this.url}/${ticketId}/resolucion`, {
      resultado_id: resultadoId,
    });
  }

  // Catalogos de clasificacion (API-01) para poblar los selectores del panel.
  // Cuelgan del mismo namespace helic3, al lado de tickets.
  catalogos() {
    return axios.get(this.url.replace(/tickets$/, 'catalogos'));
  }
}

export default new TicketsAPI();
