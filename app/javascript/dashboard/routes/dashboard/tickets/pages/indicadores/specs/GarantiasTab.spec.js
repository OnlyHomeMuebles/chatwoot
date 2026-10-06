import { shallowMount, mount, flushPromises } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
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

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
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

  // CA: un fallo del servidor no debe dejar el panel en blanco sin explicacion.
  it('muestra un aviso de error con boton de reintentar cuando el fetch falla, y reintentar vuelve a pedir', async () => {
    fetchGarantias.mockRejectedValueOnce(new Error('500'));
    const wrapper = shallowMount(GarantiasTab);
    await flushPromises();

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.ERROR');
    const reintentar = wrapper
      .findAllComponents(Button)
      .find(boton => boton.props('label') === 'HELIC3_INDICADORES.RETRY');
    expect(reintentar).toBeTruthy();

    fetchGarantias.mockClear();
    fetchGarantias.mockResolvedValueOnce();
    await reintentar.vm.$emit('click');

    expect(fetchGarantias).toHaveBeenCalledTimes(1);
  });

  describe('filtro de producto (texto libre)', () => {
    beforeEach(() => {
      garantiasRef = indicadoresVacios();
    });

    // a diferencia de los selectores (aplican de inmediato), el texto libre se
    // debounca: sin esto, cada tecla dispara una consulta y una respuesta
    // tardia de un termino viejo podria pisar una mas nueva en pantalla. Mount
    // completo (no shallow) para que el Input real dispare el v-model.
    it('no pide los indicadores de inmediato al escribir; espera el debounce', async () => {
      vi.useFakeTimers({ shouldAdvanceTime: true });
      const wrapper = mount(GarantiasTab);
      await flushPromises();
      fetchGarantias.mockClear();

      await wrapper
        .find(
          'input[placeholder="HELIC3_INDICADORES.FILTERS.PRODUCT_PLACEHOLDER"]'
        )
        .setValue('Cama');
      expect(fetchGarantias).not.toHaveBeenCalled();

      vi.advanceTimersByTime(300);
      await flushPromises();
      expect(fetchGarantias).toHaveBeenCalledTimes(1);
      expect(fetchGarantias).toHaveBeenCalledWith({ producto: 'Cama' });
      vi.useRealTimers();
    });
  });
});
