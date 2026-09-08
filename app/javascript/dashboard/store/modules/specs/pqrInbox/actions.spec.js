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

  describe('#fetchOne', () => {
    const detalle = { id: 7, numero_radicado: '#3', semaforo: 'verde' };

    it('carga el expediente en current', async () => {
      axios.get.mockResolvedValue({ data: detalle });
      await actions.fetchOne({ commit }, 7);

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingItem: true }],
        [types.SET_PQR_CURRENT, null],
        [types.SET_PQR_CURRENT, detalle],
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingItem: false }],
      ]);
    });

    it('propaga el error (404) sin dejar el flag arriba', async () => {
      axios.get.mockRejectedValue(new Error('not found'));
      await expect(actions.fetchOne({ commit }, 99)).rejects.toThrow(
        'not found'
      );

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingItem: true }],
        [types.SET_PQR_CURRENT, null],
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingItem: false }],
      ]);
    });
  });
});
