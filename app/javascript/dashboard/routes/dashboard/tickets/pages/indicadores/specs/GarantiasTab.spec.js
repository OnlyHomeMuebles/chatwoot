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
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
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
  kpis: {
    garantias: 0,
    solucionadas: 0,
    en_proceso: 0,
    productos: 0,
    facturas: 0,
    ratio: 0,
  },
  mensual: [],
  trimestral: [],
  por_ciudad: [],
  por_motivo: [],
  por_detalle: [],
  por_proceso: [],
  por_producto: [],
  motivo_por_trimestre: [],
  motivo_por_mes: [],
  detalle_por_trimestre: [],
  detalle_por_mes: [],
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

  // IND-03: el ratio garantias/facturas, paridad con el Dash CX.
  it('muestra Nº Facturas y Ratio Garantías con los kpis que trae el servidor', () => {
    garantiasRef = {
      ...indicadoresVacios(),
      kpis: {
        garantias: 5,
        solucionadas: 2,
        en_proceso: 3,
        productos: 7,
        facturas: 100,
        ratio: 5.0,
      },
    };
    const wrapper = shallowMount(GarantiasTab);

    expect(wrapper.text()).toContain('100');
    expect(wrapper.text()).toContain('5%');
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

  // N3 (revision de Jhan, PR #113): el backend devuelve etiqueta: null en vez de
  // "Sin ciudad" quemado en español; el frontend traduce con la clave del i18n.
  it('N3: traduce una etiqueta nula con la clave NO_CITY de la seccion', () => {
    garantiasRef = {
      ...indicadoresVacios(),
      kpis: { garantias: 2, solucionadas: 0, en_proceso: 2, productos: 0 },
      por_ciudad: [{ etiqueta: null, cantidad: 2 }],
    };
    const wrapper = shallowMount(GarantiasTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.GARANTIAS.NO_CITY');
  });

  // IND-03: "Centro de operacion" trae facturas y ratio por ciudad, no solo
  // la cantidad de garantias.
  it('muestra facturas y ratio por ciudad en "Centro de operacion"', () => {
    garantiasRef = {
      ...indicadoresVacios(),
      kpis: { garantias: 2, solucionadas: 0, en_proceso: 2, productos: 0 },
      por_ciudad: [
        {
          etiqueta: 'Manizales',
          valor: 1,
          cantidad: 2,
          facturas: 10,
          ratio: 20.0,
        },
      ],
    };
    const wrapper = shallowMount(GarantiasTab);

    expect(wrapper.text()).toContain('10');
    expect(wrapper.text()).toContain('20%');
  });

  // N4 (revision de Jhan, PR #113): el selector de mes muestra nombres, no 1-12.
  it('N4: el selector de mes muestra nombres de mes, no numeros', () => {
    const wrapper = mount(GarantiasTab);

    const selectorMes = wrapper.find(
      'select[aria-label="HELIC3_INDICADORES.FILTERS.MONTH"]'
    );
    const opcionesDeMes = selectorMes
      .findAll('option')
      .map(opcion => opcion.text());

    expect(opcionesDeMes).toContain('Enero');
    expect(opcionesDeMes).not.toContain('1');
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

    // Paridad con Devoluciones y con el Dash CX: clickear un producto de la
    // tabla "Por producto" filtra todo el tablero por el (mismo filtro que el
    // campo de texto, con el mismo debounce).
    it('al hacer click en un producto, lo deja como filtro y vuelve a pedir', async () => {
      vi.useFakeTimers({ shouldAdvanceTime: true });
      garantiasRef = {
        ...indicadoresVacios(),
        kpis: { garantias: 4, solucionadas: 0, en_proceso: 4, productos: 4 },
        por_producto: [{ etiqueta: 'Cama Barcelona', cantidad: 4 }],
      };
      const wrapper = mount(GarantiasTab);
      await flushPromises();
      fetchGarantias.mockClear();

      const boton = wrapper
        .findAll('button')
        .find(btn => btn.text() === 'Cama Barcelona');
      await boton.trigger('click');

      vi.advanceTimersByTime(300);
      await flushPromises();
      expect(fetchGarantias).toHaveBeenCalledWith({
        producto: 'Cama Barcelona',
      });
      vi.useRealTimers();
    });

    // El rediseño sustituye las tablas planas motivo/detalle/etapa por la
    // gráfica "Recuento por producto" (paridad con Devoluciones).
    it('muestra la gráfica "Recuento por producto"', () => {
      garantiasRef = {
        ...indicadoresVacios(),
        kpis: { garantias: 4, solucionadas: 0, en_proceso: 4, productos: 4 },
        por_producto: [{ etiqueta: 'Cama Barcelona', cantidad: 4 }],
      };
      const wrapper = shallowMount(GarantiasTab);

      expect(wrapper.text()).toContain(
        'HELIC3_INDICADORES.GARANTIAS.BY_PRODUCT_CHART'
      );
    });

    // Al hundir un producto aparece una "x" para quitar ESE filtro sin tocar
    // los demás (misma idea que la "x" de las matrices por trimestre).
    it('al hundir un producto aparece la "x" para quitar ese filtro', async () => {
      vi.useFakeTimers({ shouldAdvanceTime: true });
      garantiasRef = {
        ...indicadoresVacios(),
        kpis: { garantias: 4, solucionadas: 0, en_proceso: 4, productos: 4 },
        por_producto: [{ etiqueta: 'Cama Barcelona', cantidad: 4 }],
      };
      const wrapper = mount(GarantiasTab);
      await flushPromises();

      const boton = wrapper
        .findAll('button')
        .find(btn => btn.text() === 'Cama Barcelona');
      await boton.trigger('click');
      await flushPromises();

      const hayX = wrapper
        .findAllComponents(Button)
        .some(b => b.props('label') === 'HELIC3_INDICADORES.FILTERS.REMOVE');
      expect(hayX).toBe(true);
      vi.useRealTimers();
    });
  });

  // Paridad con el Dash CX ("Garantías por motivo"): clickear un trimestre del
  // gráfico de colores lo despliega por mes, sin pedir nada al backend (reusa
  // DesgloseTrimestral, igual que Devoluciones).
  it('al hacer click en un trimestre de "Motivo por trimestre", lo despliega por mes', async () => {
    garantiasRef = {
      ...indicadoresVacios(),
      kpis: {
        garantias: 4,
        solucionadas: 0,
        en_proceso: 4,
        productos: 0,
        facturas: 0,
        ratio: 0,
      },
      motivo_por_trimestre: [
        { motivo: 'Calidad', t1: 2, t2: 3, t3: 0, t4: 0, total: 5 },
      ],
      motivo_por_mes: [
        { motivo: 'Calidad', periodo: '2026-04', cantidad: 3 },
        { motivo: 'Calidad', periodo: '2026-01', cantidad: 2 },
      ],
    };
    const wrapper = mount(GarantiasTab);
    await flushPromises();

    const grupoT2 = wrapper
      .findAll('g')
      .find(g => g.text().trim().startsWith('T2'));
    expect(grupoT2).toBeTruthy();
    await grupoT2.trigger('click');

    expect(wrapper.text()).toContain('2026-04');
    expect(wrapper.text()).not.toContain('2026-01');
    expect(wrapper.text()).toContain(
      'HELIC3_INDICADORES.GARANTIAS.BACK_TO_QUARTERS'
    );
  });
});
