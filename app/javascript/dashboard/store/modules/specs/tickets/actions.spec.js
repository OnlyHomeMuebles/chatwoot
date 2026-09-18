import axios from 'axios';
import { actions } from '../../tickets';
import types from '../../../mutation-types';
import { ticketDetalle, catalogosData } from './fixtures';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  beforeEach(() => {
    commit.mockClear();
  });

  describe('#show', () => {
    it('pinta el detalle (semaforo/dias) sobre la fila via EDIT_TICKET', async () => {
      axios.get.mockResolvedValue({ data: ticketDetalle });
      await actions.show({ commit }, ticketDetalle.id);
      expect(commit.mock.calls).toEqual([[types.EDIT_TICKET, ticketDetalle]]);
    });

    it('no rompe la fila si el detalle falla: se traga el error sin commitear', async () => {
      axios.get.mockRejectedValue({ message: 'Error' });
      await actions.show({ commit }, ticketDetalle.id);
      expect(commit.mock.calls).toEqual([]);
    });
  });

  describe('#getCatalogos', () => {
    it('cachea los catalogos en el primer fetch', async () => {
      axios.get.mockResolvedValue({ data: catalogosData });
      const state = { catalogos: { tipos: [] } };
      await actions.getCatalogos({ commit, state });
      expect(commit.mock.calls).toEqual([
        [types.SET_TICKET_CATALOGOS, catalogosData],
      ]);
    });

    it('no vuelve a pedir si ya estan cacheados', async () => {
      const state = { catalogos: { tipos: catalogosData.tipos } };
      await actions.getCatalogos({ commit, state });
      expect(commit.mock.calls).toEqual([]);
      expect(axios.get).not.toHaveBeenCalled();
    });

    it('propaga el error en vez de degradar en silencio', async () => {
      axios.get.mockRejectedValue({ message: 'Error' });
      const state = { catalogos: { tipos: [] } };
      await expect(
        actions.getCatalogos({ commit, state })
      ).rejects.toBeTruthy();
      expect(commit.mock.calls).toEqual([]);
    });
  });
});
