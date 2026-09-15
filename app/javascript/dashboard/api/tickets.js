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
  //
  // Si el resultado abre garantia (GAR-05), el operador manda tambien el bloque
  // garantia { cobertura_ciudad_id, items: [...] }; es el MISMO endpoint, con un
  // parametro adicional. Sin garantia se omite y resuelve como siempre.
  resolver(ticketId, resultadoId, garantia = null) {
    const payload = { resultado_id: resultadoId };
    if (garantia) payload.garantia = garantia;
    return axios.post(`${this.url}/${ticketId}/resolucion`, payload);
  }

  // Registra/corrige los datos de la ficha del caso (DAT-01). Lo que el operador
  // manda aqui queda con fuente 'humano': la mas alta, no la pisa ni la IA ni el
  // ERP. La regla de precedencia la aplica el backend.
  registrarDatos(ticketId, datos) {
    return axios.patch(`${this.url}/${ticketId}/datos`, { datos });
  }

  // Avanza un producto de la garantia de proceso (GAR-03). El radicado cierra
  // solo cuando todos los productos resuelven; eso lo decide el backend.
  avanzarGarantia(garantiaId, itemId, procesoId) {
    const base = this.url.replace(/tickets$/, 'garantias');
    return axios.patch(`${base}/${garantiaId}/items/${itemId}`, {
      proceso_id: procesoId,
    });
  }

  // Catalogos de clasificacion (API-01) para poblar los selectores del panel.
  // Cuelgan del mismo namespace helic3, al lado de tickets.
  catalogos() {
    return axios.get(this.url.replace(/tickets$/, 'catalogos'));
  }
}

export default new TicketsAPI();
