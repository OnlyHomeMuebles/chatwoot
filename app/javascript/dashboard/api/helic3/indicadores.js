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
}

export default new IndicadoresAPI();
