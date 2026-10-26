/* global axios */
import ApiClient from '../ApiClient';

// FMT-04: cliente para generar formatos DESDE el expediente (ticket-scoped).
// Distinto del admin de plantillas (api/helic3/formatos.js, FMT-03): aqui la
// operadora elige formato + item, ve la vista previa con datos reales y genera.
class GenerarFormatoAPI extends ApiClient {
  constructor() {
    super('helic3', { accountScoped: true });
  }

  // prefijo .../helic3/tickets/:id/formatos para las tres operaciones.
  rutaFormatos(ticketId) {
    return `${this.baseUrl()}/helic3/tickets/${ticketId}/formatos`;
  }

  // formatos con plantilla activa + items con sugerido y marcadores vacios.
  listar(ticketId) {
    return axios.get(this.rutaFormatos(ticketId));
  }

  // vista previa en PDF (blob): la auth va en headers, por eso no se abre la URL
  // directa; el componente arma el objectURL desde el blob.
  vistaPrevia(ticketId, { formatoId, itemId }) {
    return axios.post(
      `${this.rutaFormatos(ticketId)}/vista_previa`,
      { formato_id: formatoId, item_id: itemId },
      { responseType: 'blob' }
    );
  }

  // genera y deja el documento en el expediente; devuelve el documento creado.
  generar(ticketId, { formatoId, itemId }) {
    return axios.post(this.rutaFormatos(ticketId), {
      formato_id: formatoId,
      item_id: itemId,
    });
  }
}

export default new GenerarFormatoAPI();
