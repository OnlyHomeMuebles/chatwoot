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

  // Cola de decisiones (DEC-01): lo que el agente propuso y espera a una persona.
  decisiones() {
    return axios.get(`${this.url}/decisiones`);
  }

  // Aprobar = aplicar el resultado propuesto por la unica puerta de resolucion
  // (RES-01, de Samuel), que fija origen: humano. baseUrl() da el prefijo de la
  // cuenta, sin armar la ruta a mano con replace.
  aprobar(ticketId, resultadoId) {
    return axios.post(
      `${this.baseUrl()}/helic3/tickets/${ticketId}/resolucion`,
      {
        resultado_id: resultadoId,
      }
    );
  }
}

export default new PqrInboxAPI();
