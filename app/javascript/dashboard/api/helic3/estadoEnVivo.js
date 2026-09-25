/* global axios */
import ApiClient from '../ApiClient';

// H3A-15: estado en vivo por conversación. index() = conversaciones que la IA
// atiende ahora; intervenir() pausa la IA en una conversación (un humano la toma).
class EstadoEnVivoAPI extends ApiClient {
  constructor() {
    super('helic3/estado-en-vivo', { accountScoped: true });
  }

  intervenir(conversationId) {
    return axios.post(`${this.url}/${conversationId}/intervenir`);
  }
}

export default new EstadoEnVivoAPI();
