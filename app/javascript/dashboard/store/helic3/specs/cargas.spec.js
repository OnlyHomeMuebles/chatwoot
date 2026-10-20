import { setActivePinia, createPinia } from 'pinia';
import CargasAPI from 'dashboard/api/helic3/cargas';
import { useCargasStore } from '../cargas';

vi.mock('dashboard/api/helic3/cargas', () => ({
  default: {
    get: vi.fn(),
    subir: vi.fn(),
  },
}));

describe('helic3Cargas store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  it('empieza sin cargas y sin peticiones en curso', () => {
    const store = useCargasStore();

    expect(store.getCargas).toEqual([]);
    expect(store.getUIFlags).toEqual({ isFetching: false, isSubiendo: false });
  });

  it('fetchCargas guarda la lista que trae el API', async () => {
    const payload = [{ id: 1, tipo: 'facturas' }];
    CargasAPI.get.mockResolvedValue({ data: payload });
    const store = useCargasStore();

    await store.fetchCargas();

    expect(store.getCargas).toEqual(payload);
    expect(store.getUIFlags.isFetching).toBe(false);
  });

  it('subirArchivo antepone la carga nueva a la lista y devuelve el resultado', async () => {
    const existente = { id: 1, tipo: 'facturas' };
    const nueva = { id: 2, tipo: 'facturas', estado: 'completado' };
    CargasAPI.subir.mockResolvedValue({ data: nueva });
    const store = useCargasStore();
    store.cargas = [existente];

    const resultado = await store.subirArchivo({
      tipo: 'facturas',
      modo: 'anexar',
      archivo: new Blob(),
    });

    expect(resultado).toEqual(nueva);
    expect(store.getCargas).toEqual([nueva, existente]);
  });

  it('apaga isSubiendo aunque el API falle, sin tragarse el error', async () => {
    CargasAPI.subir.mockRejectedValue(new Error('422'));
    const store = useCargasStore();

    await expect(
      store.subirArchivo({
        tipo: 'facturas',
        modo: 'anexar',
        archivo: new Blob(),
      })
    ).rejects.toThrow('422');
    expect(store.getUIFlags.isSubiendo).toBe(false);
  });
});
