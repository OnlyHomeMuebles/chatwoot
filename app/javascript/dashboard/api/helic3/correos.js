/* global axios */
import ApiClient from '../ApiClient';

// COR-04: cliente de los endpoints de plantillas de correo (COR-01/COR-02).
// Pega contra helic3/admin/plantillas_correo. vistaPrevia y prueba responden
// JSON (no un blob como las plantillas de formatos): el correo ya es HTML
// renderizado, no un archivo para descargar.
class Helic3CorreosAPI extends ApiClient {
  constructor() {
    super('helic3/admin', { accountScoped: true });
  }

  listPlantillas() {
    return axios.get(`${this.url}/plantillas_correo`);
  }

  crearPlantilla(payload) {
    return axios.post(`${this.url}/plantillas_correo`, {
      plantilla_correo: payload,
    });
  }

  actualizarPlantilla(id, payload) {
    return axios.patch(`${this.url}/plantillas_correo/${id}`, {
      plantilla_correo: payload,
    });
  }

  vistaPrevia(id) {
    return axios.post(`${this.url}/plantillas_correo/${id}/vista_previa`);
  }

  enviarPrueba(id) {
    return axios.post(`${this.url}/plantillas_correo/${id}/prueba`);
  }
}

export default new Helic3CorreosAPI();
