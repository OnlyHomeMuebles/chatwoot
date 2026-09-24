/* global axios */
import ApiClient from '../ApiClient';

// H3A-13/14: CRUD de agentes IA. El endpoint vive bajo el namespace helic3
// (/api/v1/accounts/:accountId/helic3/agentes). El indice devuelve un ARRAY plano
// (json.array!), no { payload }, asi que el store usa response.data directamente.
class AgentesIaAPI extends ApiClient {
  constructor() {
    super('helic3/agentes', { accountScoped: true });
  }

  // H3A-03: catalogo fijo de herramientas + reglas duras (solo lectura) para el editor.
  catalogo() {
    return axios.get(`${this.url}/catalogo`);
  }

  // H3A-05: prende/apaga un agente sin editar el resto.
  toggle(id) {
    return axios.patch(`${this.url}/${id}/toggle`);
  }
}

export default new AgentesIaAPI();
