/* global axios */
import ApiClient from '../ApiClient';

// IND-03 (parcial): "Carga de Datos". Solo el tipo 'facturas' tiene parser
// real hoy; los demas (IND-04) esperan a que se definan sus columnas.
class CargasAPI extends ApiClient {
  constructor() {
    super('helic3/cargas', { accountScoped: true });
  }

  subir({ tipo, modo, archivo }) {
    const datos = new FormData();
    datos.append('tipo', tipo);
    datos.append('modo', modo);
    datos.append('archivo', archivo);
    return axios.post(this.url, datos);
  }
}

export default new CargasAPI();
