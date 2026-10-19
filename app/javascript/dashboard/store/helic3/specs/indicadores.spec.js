import { setActivePinia, createPinia } from 'pinia';
import IndicadoresAPI from 'dashboard/api/helic3/indicadores';
import { useIndicadoresStore } from '../indicadores';

vi.mock('dashboard/api/helic3/indicadores', () => ({
  default: {
    garantias: vi.fn(),
    pqr: vi.fn(),
    devoluciones: vi.fn(),
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

    expect(IndicadoresAPI.garantias).toHaveBeenCalledWith(
      { anio: 2026 },
      { signal: expect.any(AbortSignal) }
    );
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

  // N2 (revision de Jhan, PR #113): el debounce reduce peticiones, pero no evita
  // que una respuesta tardia pise una mas nueva. fetchGarantias cancela la
  // peticion anterior (useAbortableRequest) e ignora su resultado si llega tarde.
  it('N2: una respuesta tardia no pisa la mas nueva', async () => {
    const store = useIndicadoresStore();
    let resolverLenta;
    IndicadoresAPI.garantias.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolverLenta = resolve;
        })
    );
    const peticionLenta = store.fetchGarantias({ anio: 2025 });

    IndicadoresAPI.garantias.mockResolvedValueOnce({
      data: { kpis: { garantias: 9 } },
    });
    await store.fetchGarantias({ anio: 2026 });

    resolverLenta({ data: { kpis: { garantias: 1 } } });
    await peticionLenta;

    expect(store.getGarantias).toEqual({ kpis: { garantias: 9 } });
  });

  it('fetchPqr pasa los filtros al API y guarda la respuesta', async () => {
    const payload = { kpis: { radicadas: 5, respondidas: 2, pendientes: 3 } };
    IndicadoresAPI.pqr.mockResolvedValue({ data: payload });
    const store = useIndicadoresStore();

    await store.fetchPqr({ anio: 2026 });

    expect(IndicadoresAPI.pqr).toHaveBeenCalledWith(
      { anio: 2026 },
      { signal: expect.any(AbortSignal) }
    );
    expect(store.getPqr).toEqual(payload);
  });

  it('isFetchingPqr es independiente de isFetchingGarantias', async () => {
    let capturado;
    IndicadoresAPI.pqr.mockImplementation(() => {
      capturado = { ...store.getUIFlags }; // eslint-disable-line no-use-before-define
      return Promise.resolve({ data: {} });
    });
    const store = useIndicadoresStore();

    await store.fetchPqr();

    expect(capturado).toEqual({
      isFetchingGarantias: false,
      isFetchingPqr: true,
      isFetchingDevoluciones: false,
    });
    expect(store.getUIFlags.isFetchingPqr).toBe(false);
  });

  it('fetchDevoluciones pasa los filtros al API y guarda la respuesta', async () => {
    const payload = {
      kpis: { devoluciones: 4, solucionadas: 1, en_proceso: 3, productos: 5 },
    };
    IndicadoresAPI.devoluciones.mockResolvedValue({ data: payload });
    const store = useIndicadoresStore();

    await store.fetchDevoluciones({ anio: 2026 });

    expect(IndicadoresAPI.devoluciones).toHaveBeenCalledWith(
      { anio: 2026 },
      { signal: expect.any(AbortSignal) }
    );
    expect(store.getDevoluciones).toEqual(payload);
  });
});
