import axios from 'axios';
import { actions } from '../../pqrCatalogos';
import types from '../../../mutation-types';

const commit = vi.fn();
const dispatch = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  beforeEach(() => {
    commit.mockClear();
    dispatch.mockClear();
  });

  describe('#fetchCatalogo', () => {
    it('guarda el catalogo por tipo', async () => {
      const registros = [
        { id: 1, codigo: 'garantia_producto', nombre: 'Garantía' },
      ];
      axios.get.mockResolvedValue({ data: registros });

      await actions.fetchCatalogo({ commit }, 'motivos_pqr');

      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_ADMIN_UI_FLAG, { isFetching: true }],
        [types.SET_PQR_CATALOGO, { tipo: 'motivos_pqr', registros }],
        [types.SET_PQR_ADMIN_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#createCatalogo', () => {
    it('crea y recarga el catalogo afectado', async () => {
      axios.post.mockResolvedValue({ data: { id: 2 } });

      await actions.createCatalogo(
        { commit, dispatch },
        { tipo: 'resultados', data: { nombre: 'Procede', codigo: 'procede' } }
      );

      expect(dispatch).toHaveBeenCalledWith('fetchCatalogo', 'resultados');
      expect(commit.mock.calls).toEqual([
        [types.SET_PQR_ADMIN_UI_FLAG, { isSaving: true }],
        [types.SET_PQR_ADMIN_UI_FLAG, { isSaving: false }],
      ]);
    });
  });

  describe('#updateParametro', () => {
    it('actualiza y recarga los parametros', async () => {
      axios.patch.mockResolvedValue({ data: { id: 5 } });

      await actions.updateParametro(
        { commit, dispatch },
        { id: 5, data: { valor: '15' } }
      );

      expect(dispatch).toHaveBeenCalledWith('fetchParametros');
    });
  });
});
