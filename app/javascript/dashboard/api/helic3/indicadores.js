/* global axios */
import ApiClient from '../ApiClient';

// IND-01/IND-02: cliente de la seccion "Indicadores" (lo que hoy se consulta
// en el Dash CX externo). Un metodo por pestaña.
class IndicadoresAPI extends ApiClient {
  constructor() {
    super('helic3/indicadores', { accountScoped: true });
  }

  garantias(params, { signal } = {}) {
    return axios.get(`${this.url}/garantias`, { params, signal });
  }

  pqr(params, { signal } = {}) {
    return axios.get(`${this.url}/pqr`, { params, signal });
  }

  devoluciones(params, { signal } = {}) {
    return axios.get(`${this.url}/devoluciones`, { params, signal });
  }

  // Detalle de clientes y casos (mismo patron de garantiasCasos).
  devolucionesCasos(params, { signal } = {}) {
    return axios.get(`${this.url}/devoluciones/casos`, { params, signal });
  }

  // IND-05: misma tabla, mismos filtros, en CSV. responseType: 'blob' para que
  // axios no intente parsear el cuerpo como JSON.
  garantiasCsv(seccion, params = {}) {
    return axios.get(`${this.url}/garantias/csv`, {
      params: { ...params, seccion },
      responseType: 'blob',
    });
  }

  pqrCsv(seccion, params = {}) {
    return axios.get(`${this.url}/pqr/csv`, {
      params: { ...params, seccion },
      responseType: 'blob',
    });
  }

  devolucionesCsv(seccion, params = {}) {
    return axios.get(`${this.url}/devoluciones/csv`, {
      params: { ...params, seccion },
      responseType: 'blob',
    });
  }
}

export default new IndicadoresAPI();
