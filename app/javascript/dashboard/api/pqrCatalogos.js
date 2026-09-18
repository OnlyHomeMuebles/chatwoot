/* global axios */
import ApiClient from './ApiClient';

// Cliente de administracion de catalogos y parametros (ADM-01). Pega contra
// helic3/admin/*. Lectura para agentes; la escritura la rechaza el backend con
// 401 si quien llama no es administrador.
class PqrCatalogosAPI extends ApiClient {
  constructor() {
    super('helic3/admin', { accountScoped: true });
  }

  listCatalogo(tipo) {
    return axios.get(`${this.url}/catalogos/${tipo}`);
  }

  createCatalogo(tipo, catalogo) {
    return axios.post(`${this.url}/catalogos/${tipo}`, { catalogo });
  }

  updateCatalogo(tipo, id, catalogo) {
    return axios.patch(`${this.url}/catalogos/${tipo}/${id}`, { catalogo });
  }

  deleteCatalogo(tipo, id) {
    return axios.delete(`${this.url}/catalogos/${tipo}/${id}`);
  }

  listParametros() {
    return axios.get(`${this.url}/parametros`);
  }

  updateParametro(id, parametro) {
    return axios.patch(`${this.url}/parametros/${id}`, { parametro });
  }
}

export default new PqrCatalogosAPI();
