import { setActivePinia, createPinia } from 'pinia';
import IndicadoresAPI from 'dashboard/api/helic3/indicadores';
import { useIndicadoresStore } from '../indicadores';

vi.mock('dashboard/api/helic3/indicadores', () => ({
  default: {
    garantias: vi.fn(),
  },
}));

describe('helic3Indicadores store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  it('empieza sin datos y sin cargar', () => {
    const store = useIndicadoresStore();

    expect(store.getGarantias).toBeNull();
    expect(store.getUIFlags.isFetchingGarantias).toBe(false);
  });

  it('fetchGarantias pasa los filtros al API y guarda la respuesta', async () => {
    const payload = {
      kpis: { garantias: 3, solucionadas: 1, en_proceso: 2, productos: 4 },
    };
    IndicadoresAPI.garantias.mockResolvedValue({ data: payload });
    const store = useIndicadoresStore();

    await store.fetchGarantias({ anio: 2026 });

    expect(IndicadoresAPI.garantias).toHaveBeenCalledWith({ anio: 2026 });
    expect(store.getGarantias).toEqual(payload);
  });

  it('prende y apaga isFetchingGarantias alrededor de la peticion', async () => {
    let capturado;
    IndicadoresAPI.garantias.mockImplementation(() => {
      capturado = store.getUIFlags.isFetchingGarantias; // eslint-disable-line no-use-before-define
      return Promise.resolve({ data: {} });
    });
    const store = useIndicadoresStore();

    await store.fetchGarantias();

    expect(capturado).toBe(true);
    expect(store.getUIFlags.isFetchingGarantias).toBe(false);
  });

  it('apaga isFetchingGarantias aunque el API falle, sin tragarse el error', async () => {
    IndicadoresAPI.garantias.mockRejectedValue(new Error('500'));
    const store = useIndicadoresStore();

    await expect(store.fetchGarantias()).rejects.toThrow('500');
    expect(store.getUIFlags.isFetchingGarantias).toBe(false);
  });
});
