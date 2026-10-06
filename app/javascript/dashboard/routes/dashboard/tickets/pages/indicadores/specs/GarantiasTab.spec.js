import { shallowMount } from '@vue/test-utils';
import GarantiasTab from '../GarantiasTab.vue';

// vi.mock(...) se iza (hoisted) al tope del archivo; vi.hoisted() es la forma
// documentada de compartir con seguridad un mock entre esa fabrica y el resto
// del archivo, sin pisar el "no uses variables de nivel superior" del aviso
// de vitest.
const { dispatch, fetchGarantias, catalogosRef } = vi.hoisted(() => ({
  dispatch: vi.fn().mockResolvedValue(),
  fetchGarantias: vi.fn().mockResolvedValue(),
  catalogosRef: {
    value: {
      coberturas_ciudad: [{ id: 1, nombre: 'Manizales' }],
      motivos_garantia: [{ id: 2, nombre: 'Calidad' }],
      detalles_tipificados: [],
      procesos_garantia: [],
    },
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => catalogosRef,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

let garantiasRef;
let uiFlagsRef;

vi.mock('dashboard/store/helic3/indicadores', () => ({
  useIndicadoresStore: () => ({
    get getGarantias() {
      return garantiasRef;
    },
    get getUIFlags() {
      return uiFlagsRef;
    },
    fetchGarantias,
  }),
}));

const indicadoresVacios = () => ({
  kpis: { garantias: 0, solucionadas: 0, en_proceso: 0, productos: 0 },
  mensual: [],
  trimestral: [],
  por_ciudad: [],
  por_motivo: [],
  por_detalle: [],
  por_proceso: [],
  por_producto: [],
});

describe('GarantiasTab.vue (IND-01)', () => {
  beforeEach(() => {
    dispatch.mockClear();
    fetchGarantias.mockClear();
    garantiasRef = null;
    uiFlagsRef = { isFetchingGarantias: false };
  });

  it('al montar, trae los catalogos (GAR-05/IND-01) y pide los indicadores sin filtros', () => {
    shallowMount(GarantiasTab);

    expect(dispatch).toHaveBeenCalledWith('tickets/getCatalogos');
    expect(fetchGarantias).toHaveBeenCalledWith({});
  });

  it('no muestra tarjetas ni el aviso de vacio mientras esta cargando', () => {
    uiFlagsRef = { isFetchingGarantias: true };
    const wrapper = shallowMount(GarantiasTab);

    expect(wrapper.text()).not.toContain('HELIC3_INDICADORES.EMPTY');
    expect(wrapper.text()).not.toContain(
      'HELIC3_INDICADORES.GARANTIAS.KPI_TOTAL'
    );
  });

  it('CA: muestra el aviso de "sin datos" cuando el filtro no trae garantias', () => {
    garantiasRef = indicadoresVacios();
    const wrapper = shallowMount(GarantiasTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.EMPTY');
  });

  it('muestra las cuatro tarjetas con los kpis que trae el servidor', () => {
    garantiasRef = {
      ...indicadoresVacios(),
      kpis: { garantias: 5, solucionadas: 2, en_proceso: 3, productos: 7 },
    };
    const wrapper = shallowMount(GarantiasTab);

    expect(wrapper.text()).toContain('5');
    expect(wrapper.text()).toContain('2');
    expect(wrapper.text()).toContain('3');
    expect(wrapper.text()).toContain('7');
  });
});
