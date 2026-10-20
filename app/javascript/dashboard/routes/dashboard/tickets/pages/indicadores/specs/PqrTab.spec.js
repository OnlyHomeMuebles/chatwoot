import { shallowMount, mount, flushPromises } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import PqrTab from '../PqrTab.vue';

// vi.mock(...) se iza (hoisted) al tope del archivo; vi.hoisted() es la forma
// documentada de compartir con seguridad un mock entre esa fabrica y el resto
// del archivo (mismo patron de GarantiasTab.spec.js).
const { dispatch, fetchPqr, catalogosRef, agentesRef } = vi.hoisted(() => ({
  dispatch: vi.fn().mockResolvedValue(),
  fetchPqr: vi.fn().mockResolvedValue(),
  catalogosRef: {
    value: {
      tipos: [{ id: 1, nombre: 'Reclamo' }],
      motivos_pqr: [{ id: 2, nombre: 'Calidad' }],
    },
  },
  agentesRef: { value: [{ id: 3, name: 'Juan' }] },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key => (key === 'agents/getAgents' ? agentesRef : catalogosRef),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

let pqrRef;
let uiFlagsRef;

vi.mock('dashboard/store/helic3/indicadores', () => ({
  useIndicadoresStore: () => ({
    get getPqr() {
      return pqrRef;
    },
    get getUIFlags() {
      return uiFlagsRef;
    },
    fetchPqr,
  }),
}));

const indicadoresVacios = () => ({
  kpis: {
    radicadas: 0,
    respondidas: 0,
    pendientes: 0,
    pct_respondidas: null,
    dentro_plazo: 0,
    vencidas_sin_responder: 0,
    pct_cumplimiento: null,
  },
  mensual: [],
  trimestral: [],
  motivo_por_trimestre: [],
  por_tipo: [],
  por_categoria: [],
  por_resultado: [],
  por_responsable: [],
});

describe('PqrTab.vue (IND-02)', () => {
  beforeEach(() => {
    dispatch.mockClear();
    fetchPqr.mockClear();
    pqrRef = null;
    uiFlagsRef = { isFetchingPqr: false };
  });

  it('al montar, trae catalogos y agentes, y pide los indicadores sin filtros', () => {
    shallowMount(PqrTab);

    expect(dispatch).toHaveBeenCalledWith('tickets/getCatalogos');
    expect(dispatch).toHaveBeenCalledWith('agents/get');
    expect(fetchPqr).toHaveBeenCalledWith({});
  });

  it('no muestra tarjetas ni el aviso de vacio mientras esta cargando', () => {
    uiFlagsRef = { isFetchingPqr: true };
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).not.toContain('HELIC3_INDICADORES.EMPTY');
    expect(wrapper.text()).not.toContain('HELIC3_INDICADORES.PQR.KPI_FILED');
  });

  it('CA: muestra el aviso de "sin datos" cuando el filtro no trae PQR', () => {
    pqrRef = indicadoresVacios();
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.EMPTY');
  });

  it('muestra las tarjetas con los kpis que trae el servidor, incluyendo los porcentajes', () => {
    pqrRef = {
      ...indicadoresVacios(),
      kpis: {
        radicadas: 10,
        respondidas: 6,
        pendientes: 4,
        pct_respondidas: 60.0,
        dentro_plazo: 5,
        vencidas_sin_responder: 2,
        pct_cumplimiento: 83.3,
      },
    };
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).toContain('10');
    expect(wrapper.text()).toContain('60%');
    expect(wrapper.text()).toContain('83.3%');
  });

  it('sin respondidas, pct_cumplimiento nulo se muestra como guion, no 0%', () => {
    pqrRef = {
      ...indicadoresVacios(),
      kpis: { ...indicadoresVacios().kpis, radicadas: 1, pendientes: 1 },
    };
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).toContain('—');
  });

  it('muestra un aviso de error con boton de reintentar cuando el fetch falla, y reintentar vuelve a pedir', async () => {
    fetchPqr.mockRejectedValueOnce(new Error('500'));
    const wrapper = shallowMount(PqrTab);
    await flushPromises();

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.ERROR');
    const reintentar = wrapper
      .findAllComponents(Button)
      .find(boton => boton.props('label') === 'HELIC3_INDICADORES.RETRY');
    expect(reintentar).toBeTruthy();

    fetchPqr.mockClear();
    fetchPqr.mockResolvedValueOnce();
    await reintentar.vm.$emit('click');

    expect(fetchPqr).toHaveBeenCalledTimes(1);
  });

  // Mismo patron N3 de GarantiasTab.vue: el backend devuelve etiqueta/motivo
  // null en vez de texto quemado en español.
  it('traduce un responsable nulo como "Sin asignar" (TICKETS.UNASSIGNED)', () => {
    pqrRef = {
      ...indicadoresVacios(),
      kpis: { ...indicadoresVacios().kpis, radicadas: 1, pendientes: 1 },
      por_responsable: [{ etiqueta: null, cantidad: 1 }],
    };
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).toContain('TICKETS.UNASSIGNED');
  });

  it('traduce un resultado nulo con la clave NO_RESULT', () => {
    pqrRef = {
      ...indicadoresVacios(),
      kpis: { ...indicadoresVacios().kpis, radicadas: 1, pendientes: 1 },
      por_resultado: [{ etiqueta: null, cantidad: 1 }],
    };
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.PQR.NO_RESULT');
  });

  // Caso real encontrado en datos sembrados: tipo/categoria son opcionales en
  // el ticket -- una etiqueta nula no debe quedar en blanco en la tabla.
  it('traduce un tipo o categoria nulos con NO_TYPE/NO_CATEGORY', () => {
    pqrRef = {
      ...indicadoresVacios(),
      kpis: { ...indicadoresVacios().kpis, radicadas: 1, pendientes: 1 },
      por_tipo: [{ etiqueta: null, cantidad: 1 }],
      por_categoria: [{ etiqueta: null, cantidad: 1 }],
    };
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.PQR.NO_TYPE');
    expect(wrapper.text()).toContain('HELIC3_INDICADORES.PQR.NO_CATEGORY');
  });

  it('motivo_por_trimestre: muestra cada trimestre y el total', () => {
    pqrRef = {
      ...indicadoresVacios(),
      kpis: { ...indicadoresVacios().kpis, radicadas: 3, respondidas: 3 },
      motivo_por_trimestre: [
        { motivo: 'Calidad', t1: 2, t2: 0, t3: 0, t4: 0, total: 2 },
      ],
    };
    const wrapper = shallowMount(PqrTab);

    expect(wrapper.text()).toContain('Calidad');
    expect(wrapper.text()).toContain('T1');
  });

  it('el selector de mes muestra nombres de mes, no numeros', () => {
    const wrapper = mount(PqrTab);

    const selectorMes = wrapper.find(
      'select[aria-label="HELIC3_INDICADORES.FILTERS.MONTH"]'
    );
    const opcionesDeMes = selectorMes
      .findAll('option')
      .map(opcion => opcion.text());

    expect(opcionesDeMes).toContain('Enero');
    expect(opcionesDeMes).not.toContain('1');
  });

  it('el selector de responsable lista los agentes de la cuenta', () => {
    const wrapper = mount(PqrTab);

    const selectorResponsable = wrapper.find(
      'select[aria-label="HELIC3_INDICADORES.FILTERS.RESPONSIBLE"]'
    );
    const opciones = selectorResponsable
      .findAll('option')
      .map(opcion => opcion.text());

    expect(opciones).toContain('Juan');
  });

  it('limpiar filtros vuelve a pedir los indicadores sin parametros', async () => {
    pqrRef = indicadoresVacios();
    const wrapper = mount(PqrTab);
    await flushPromises();

    const selectorAnio = wrapper.find(
      'select[aria-label="HELIC3_INDICADORES.FILTERS.YEAR"]'
    );
    await selectorAnio.setValue(String(new Date().getFullYear()));
    await flushPromises();
    fetchPqr.mockClear();

    const limpiar = wrapper
      .findAllComponents(Button)
      .find(
        boton => boton.props('label') === 'HELIC3_INDICADORES.FILTERS.CLEAR'
      );
    await limpiar.vm.$emit('click');
    await flushPromises();

    expect(fetchPqr).toHaveBeenCalledWith({});
  });
});
