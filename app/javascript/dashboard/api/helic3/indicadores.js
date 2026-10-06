/* global axios */
import ApiClient from '../ApiClient';

// IND-01: cliente de la seccion "Indicadores" (lo que hoy se consulta en el
// Dash CX externo). Una pestaña, un metodo -- IND-02 suma `pqr(params)`.
class IndicadoresAPI extends ApiClient {
  constructor() {
    super('helic3/indicadores', { accountScoped: true });
  }

  garantias(params) {
    return axios.get(`${this.url}/garantias`, { params });
  }
}

export default new IndicadoresAPI();
