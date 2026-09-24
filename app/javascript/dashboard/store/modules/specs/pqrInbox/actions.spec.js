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
      metricas: { total: 42, sin_responder: 5, vencidas: 2, respondidas: 37 },
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
            metricas: {
              total: 42,
              sin_responder: 5,
              vencidas: 2,
              respondidas: 37,
            },
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

  describe('#fetchDocumentos', () => {
    it('carga el archivo documental del expediente', async () => {
      const documentos = [{ id: 1, clase: 'evidencia', titulo: 'foto.png' }];
      axios.get.mockResolvedValue({ data: documentos });

      await actions.fetchDocumentos({ commit }, 7);

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingDocumentos: true }],
        [types.SET_PQR_DOCUMENTOS, documentos],
        [types.SET_PQR_INBOX_UI_FLAG, { isFetchingDocumentos: false }],
      ]);
    });
  });

  describe('#subirDocumento', () => {
    it('sube el documento y lo suma a la lista', async () => {
      const nuevo = { id: 9, clase: 'evidencia', origen: 'operador' };
      axios.post.mockResolvedValue({ data: nuevo });
      const formData = new FormData();

      await actions.subirDocumento({ commit }, { id: 7, formData });

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isUploadingDocumento: true }],
        [types.ADD_PQR_DOCUMENTO, nuevo],
        [types.SET_PQR_INBOX_UI_FLAG, { isUploadingDocumento: false }],
      ]);
    });

    it('propaga el error y baja el flag de carga', async () => {
      axios.post.mockRejectedValue(new Error('boom'));

      await expect(
        actions.subirDocumento({ commit }, { id: 7, formData: new FormData() })
      ).rejects.toThrow('boom');

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_INBOX_UI_FLAG, { isUploadingDocumento: true }],
        [types.SET_PQR_INBOX_UI_FLAG, { isUploadingDocumento: false }],
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

  describe('#actualizar', () => {
    it('cambia el estado y refresca el expediente actual', async () => {
      const actualizado = { id: 7, status: 'pending' };
      axios.patch.mockResolvedValue({ data: actualizado });

      await actions.actualizar(
        { commit },
        { id: 7, data: { status: 'pending' } }
      );

      expect(commit).toHaveBeenCalledWith(types.SET_PQR_CURRENT, actualizado);
    });
  });

  describe('#asignar', () => {
    it('reasigna y refresca el expediente actual', async () => {
      const actualizado = { id: 7, assignee: { id: 3 } };
      axios.post.mockResolvedValue({ data: actualizado });

      await actions.asignar({ commit }, { id: 7, assigneeId: 3 });

      expect(commit).toHaveBeenCalledWith(types.SET_PQR_CURRENT, actualizado);
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
