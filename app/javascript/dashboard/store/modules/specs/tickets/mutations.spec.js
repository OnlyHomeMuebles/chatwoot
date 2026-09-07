import { mutations } from '../../tickets';
import types from '../../../mutation-types';
import { catalogosData } from './fixtures';

describe('#mutations', () => {
  describe('#SET_TICKET_CATALOGOS', () => {
    it('reemplaza los catalogos con los que llegan del API', () => {
      const state = {
        catalogos: {
          tipos: [],
          motivos_pqr: [],
          etapas_pqr: [],
          resultados: [],
        },
      };
      mutations[types.SET_TICKET_CATALOGOS](state, catalogosData);
      expect(state.catalogos).toEqual(catalogosData);
    });
  });
});
