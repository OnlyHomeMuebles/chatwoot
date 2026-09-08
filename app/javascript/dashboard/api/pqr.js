/* global axios */
import ApiClient from './ApiClient';

// Cliente propio de la bandeja de PQR (BAN-01): pega contra GET helic3/pqr, el
// indice paginado y filtrado en servidor. Separado del cliente del panel de
// conversacion (api/tickets.js) a proposito: son dos consumidores distintos.
class PqrInboxAPI extends ApiClient {
  constructor() {
    super('helic3/pqr', { accountScoped: true });
  }

  // params: categoria_id, tipo_id, etapa_id, assignee_id, q, vencidas, page
  list(params = {}) {
    return axios.get(this.url, { params });
  }

  // Detalle del expediente (DET-01): consume el show ya existente de tickets, que
  // trae semaforo, dias_habiles_restantes, los sellos y la clasificacion.
  detalle(id) {
    return axios.get(`${this.url.replace(/pqr$/, 'tickets')}/${id}`);
  }
}

export default new PqrInboxAPI();
