import axios from 'axios';
import { actions } from '../../pqrInbox';
import types from '../../../mutation-types';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

const respuesta = {
  data: {
    meta: {
      count: 42,
      current_page: 1,
      per_page: 25,
      umbral_verde: 8,
      umbral_amarillo: 3,
    },
    payload: [
      { id: 7, numero_radicado: '#3', title: 'Sofá rayado' },
      { id: 8, numero_radicado: null, title: 'Consulta' },
    ],
  },
};

describe('#actions', () => {
  beforeEach(() => commit.mockClear());

  describe('#fetch', () => {
    it('carga la pagina y su total (payload + meta)', async () => {
      axios.get.mockResolvedValue(respuesta);
      await actions.fetch({ commit }, { categoria_id: 5 });

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isFetching: true }],
        [types.SET_PQR_INBOX, respuesta.data.payload],
        [
          types.SET_PQR_INBOX_META,
          {
            count: 42,
            currentPage: 1,
            perPage: 25,
            umbralVerde: 8,
            umbralAmarillo: 3,
          },
        ],
        [types.SET_PQR_INBOX_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('propaga el error y baja el flag de carga', async () => {
      axios.get.mockRejectedValue(new Error('boom'));
      await expect(actions.fetch({ commit }, {})).rejects.toThrow('boom');

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isFetching: true }],
        [types.SET_PQR_INBOX_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#fetchDecisiones', () => {
    it('carga la cola de decisiones', async () => {
      const cola = [
        { id: 7, propuesta: { id: 3, nombre: 'No procede garantía' } },
      ];
      axios.get.mockResolvedValue({ data: cola });

      await actions.fetchDecisiones({ commit });

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingDecisiones: true }],
        [types.SET_PQR_DECISIONES, cola],
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingDecisiones: false }],
      ]);
    });
  });

  describe('#aprobarDecision', () => {
    it('aprueba por la resolucion y recarga la cola', async () => {
      const dispatch = vi.fn();
      axios.post.mockResolvedValue({ data: {} });

      await actions.aprobarDecision(
        { dispatch },
        { ticketId: 7, resultadoId: 3 }
      );

      expect(dispatch).toHaveBeenCalledWith('fetchDecisiones');
    });

    it('propaga el error (401 de un agente) sin recargar', async () => {
      const dispatch = vi.fn();
      axios.post.mockRejectedValue({ response: { status: 401 } });

      await expect(
        actions.aprobarDecision({ dispatch }, { ticketId: 7, resultadoId: 3 })
      ).rejects.toBeTruthy();
      expect(dispatch).not.toHaveBeenCalled();
    });
  });
});
