import { shallowMount, mount, flushPromises } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import DevolucionesTab from '../DevolucionesTab.vue';

const { dispatch, fetchDevoluciones, catalogosRef } = vi.hoisted(() => ({
  dispatch: vi.fn().mockResolvedValue(),
  fetchDevoluciones: vi.fn().mockResolvedValue(),
  catalogosRef: {
    value: {
      coberturas_ciudad: [{ id: 1, nombre: 'Manizales' }],
      motivos_devolucion: [{ id: 2, nombre: 'Cambio de talla' }],
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
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

let devolucionesRef;
let uiFlagsRef;

vi.mock('dashboard/store/helic3/indicadores', () => ({
  useIndicadoresStore: () => ({
    get getDevoluciones() {
      return devolucionesRef;
    },
    get getUIFlags() {
      return uiFlagsRef;
    },
    fetchDevoluciones,
  }),
}));

const indicadoresVacios = () => ({
  kpis: { devoluciones: 0, solucionadas: 0, en_proceso: 0, productos: 0 },
  mensual: [],
  trimestral: [],
  por_ciudad: [],
  por_motivo: [],
  por_detalle: [],
  por_proceso: [],
  por_producto: [],
});

describe('DevolucionesTab.vue (IND-06)', () => {
  beforeEach(() => {
    dispatch.mockClear();
    fetchDevoluciones.mockClear();
    devolucionesRef = null;
    uiFlagsRef = { isFetchingDevoluciones: false };
  });

  it('al montar, trae los catalogos y pide los indicadores sin filtros', () => {
    shallowMount(DevolucionesTab);

    expect(dispatch).toHaveBeenCalledWith('tickets/getCatalogos');
    expect(fetchDevoluciones).toHaveBeenCalledWith({});
  });

  it('CA: muestra el aviso de "sin datos" cuando el filtro no trae devoluciones', () => {
    devolucionesRef = indicadoresVacios();
    const wrapper = shallowMount(DevolucionesTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.EMPTY');
  });

  it('muestra las cuatro tarjetas con los kpis que trae el servidor', () => {
    devolucionesRef = {
      ...indicadoresVacios(),
      kpis: { devoluciones: 5, solucionadas: 2, en_proceso: 3, productos: 7 },
    };
    const wrapper = shallowMount(DevolucionesTab);

    expect(wrapper.text()).toContain('5');
    expect(wrapper.text()).toContain('2');
    expect(wrapper.text()).toContain('3');
    expect(wrapper.text()).toContain('7');
  });

  it('muestra un aviso de error con boton de reintentar cuando el fetch falla, y reintentar vuelve a pedir', async () => {
    fetchDevoluciones.mockRejectedValueOnce(new Error('500'));
    const wrapper = shallowMount(DevolucionesTab);
    await flushPromises();

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.ERROR');
    const reintentar = wrapper
      .findAllComponents(Button)
      .find(boton => boton.props('label') === 'HELIC3_INDICADORES.RETRY');
    expect(reintentar).toBeTruthy();

    fetchDevoluciones.mockClear();
    fetchDevoluciones.mockResolvedValueOnce();
    await reintentar.vm.$emit('click');

    expect(fetchDevoluciones).toHaveBeenCalledTimes(1);
  });

  // N3 (mismo criterio de GarantiasTab.vue): etiqueta nula -> traducida con NO_CITY.
  it('traduce una etiqueta nula con la clave NO_CITY de la seccion', () => {
    devolucionesRef = {
      ...indicadoresVacios(),
      kpis: { devoluciones: 2, solucionadas: 0, en_proceso: 2, productos: 0 },
      por_ciudad: [{ etiqueta: null, cantidad: 2 }],
    };
    const wrapper = shallowMount(DevolucionesTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.DEVOLUCIONES.NO_CITY');
  });

  describe('filtro de producto (texto libre)', () => {
    beforeEach(() => {
      devolucionesRef = indicadoresVacios();
    });

    it('no pide los indicadores de inmediato al escribir; espera el debounce', async () => {
      vi.useFakeTimers({ shouldAdvanceTime: true });
      const wrapper = mount(DevolucionesTab);
      await flushPromises();
      fetchDevoluciones.mockClear();

      await wrapper
        .find(
          'input[placeholder="HELIC3_INDICADORES.FILTERS.PRODUCT_PLACEHOLDER"]'
        )
        .setValue('Silla');
      expect(fetchDevoluciones).not.toHaveBeenCalled();

      vi.advanceTimersByTime(300);
      await flushPromises();
      expect(fetchDevoluciones).toHaveBeenCalledTimes(1);
      expect(fetchDevoluciones).toHaveBeenCalledWith({ producto: 'Silla' });
      vi.useRealTimers();
    });
  });

  // Paridad con el Dash CX ("Devoluciones por motivo"): clickear un
  // trimestre del grafico de colores lo despliega por mes, sin pedir nada
  // al backend (motivo_por_mes ya viaja completo en la misma respuesta).
  it('al hacer click en un trimestre de "Motivo por trimestre", lo despliega por mes', async () => {
    devolucionesRef = {
      ...indicadoresVacios(),
      kpis: { devoluciones: 4, solucionadas: 0, en_proceso: 4, productos: 0 },
      motivo_por_trimestre: [
        { motivo: 'Cambio de talla', t1: 2, t2: 3, t3: 0, t4: 0, total: 5 },
      ],
      motivo_por_mes: [
        { motivo: 'Cambio de talla', periodo: '2026-04', cantidad: 3 },
        { motivo: 'Cambio de talla', periodo: '2026-01', cantidad: 2 },
      ],
    };
    const wrapper = mount(DevolucionesTab);
    await flushPromises();

    const grupoT2 = wrapper
      .findAll('g')
      .find(g => g.text().trim().startsWith('T2'));
    expect(grupoT2).toBeTruthy();
    await grupoT2.trigger('click');

    expect(wrapper.text()).toContain('2026-04');
    expect(wrapper.text()).not.toContain('2026-01');
    expect(wrapper.text()).toContain(
      'HELIC3_INDICADORES.DEVOLUCIONES.BACK_TO_QUARTERS'
    );
  });

  // Paridad con el Dash CX: "Producto" es un filtro global mas -- clickear
  // un producto en "Por producto" filtra todo el tablero por ese producto,
  // igual que clickear una ciudad.
  it('al hacer click en un producto, lo deja como filtro y vuelve a pedir los indicadores', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    devolucionesRef = {
      ...indicadoresVacios(),
      kpis: { devoluciones: 4, solucionadas: 0, en_proceso: 4, productos: 4 },
      por_producto: [{ etiqueta: 'Sofá Modular Santorini', cantidad: 4 }],
    };
    const wrapper = mount(DevolucionesTab);
    await flushPromises();
    fetchDevoluciones.mockClear();

    const boton = wrapper
      .findAll('button')
      .find(btn => btn.text() === 'Sofá Modular Santorini');
    await boton.trigger('click');

    vi.advanceTimersByTime(300);
    await flushPromises();
    expect(fetchDevoluciones).toHaveBeenCalledWith({
      producto: 'Sofá Modular Santorini',
    });
    vi.useRealTimers();
  });
});
