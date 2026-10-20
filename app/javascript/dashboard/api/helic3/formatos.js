/* global axios */
import ApiClient from '../ApiClient';

// FMT-03: cliente de los endpoints de formatos/plantillas (FMT-02). Pega contra
// helic3/admin/*. La vista previa y la descarga piden el archivo como blob porque
// la autenticacion va en las cabeceras (un iframe/<a> directo no la llevaria).
class Helic3FormatosAPI extends ApiClient {
  constructor() {
    super('helic3/admin', { accountScoped: true });
  }

  listFormatos() {
    return axios.get(`${this.url}/formatos`);
  }

  marcadores() {
    return axios.get(`${this.url}/formatos/marcadores`);
  }

  subirPlantilla(formatoId, formData) {
    return axios.post(
      `${this.url}/formatos/${formatoId}/plantillas`,
      formData,
      {
        headers: { 'Content-Type': 'multipart/form-data' },
      }
    );
  }

  vistaPrevia(plantillaId, formato = 'pdf') {
    return axios.get(`${this.url}/plantillas/${plantillaId}/vista_previa`, {
      params: { formato },
      responseType: 'blob',
    });
  }

  descargarOriginal(plantillaId) {
    return axios.get(`${this.url}/plantillas/${plantillaId}/original`, {
      responseType: 'blob',
    });
  }

  activar(plantillaId) {
    return axios.post(`${this.url}/plantillas/${plantillaId}/activar`);
  }

  descartar(plantillaId) {
    return axios.delete(`${this.url}/plantillas/${plantillaId}`);
  }

  // FMT-06: crear/actualizar el formato mismo (no sus plantillas) por el CRUD
  // generico de catalogos. Asi Karen agrega o desactiva formatos sin devs.
  crearFormato(payload) {
    return axios.post(`${this.url}/catalogos/formatos`, { catalogo: payload });
  }

  actualizarFormato(id, payload) {
    return axios.patch(`${this.url}/catalogos/formatos/${id}`, {
      catalogo: payload,
    });
  }
}

export default new Helic3FormatosAPI();
