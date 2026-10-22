import { shallowMount, flushPromises } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import TodasTab from '../TodasTab.vue';

const { fetchTodas } = vi.hoisted(() => ({
  fetchTodas: vi.fn().mockResolvedValue(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

let todasRef;
let uiFlagsRef;

vi.mock('dashboard/store/helic3/indicadores', () => ({
  useIndicadoresStore: () => ({
    get getTodas() {
      return todasRef;
    },
    get getUIFlags() {
      return uiFlagsRef;
    },
    fetchTodas,
  }),
}));

const indicadoresVacios = () => ({
  kpis: {
    total_casos: 0,
    garantias: 0,
    pqr: 0,
    solucionadas: 0,
    en_proceso: 0,
  },
  mensual: [],
  trimestral: [],
});

describe('TodasTab.vue', () => {
  beforeEach(() => {
    fetchTodas.mockClear();
    todasRef = null;
    uiFlagsRef = { isFetchingTodas: false };
  });

  it('al montar, pide el resumen sin filtros', () => {
    shallowMount(TodasTab);

    expect(fetchTodas).toHaveBeenCalledWith({});
  });

  it('muestra el aviso de "sin datos" cuando el total combinado es 0', () => {
    todasRef = indicadoresVacios();
    const wrapper = shallowMount(TodasTab);

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.EMPTY');
  });

  it('suma garantias + pqr en la tarjeta de total', () => {
    todasRef = {
      ...indicadoresVacios(),
      kpis: {
        total_casos: 7,
        garantias: 4,
        pqr: 3,
        solucionadas: 2,
        en_proceso: 5,
      },
    };
    const wrapper = shallowMount(TodasTab);

    expect(wrapper.text()).toContain('7');
    expect(wrapper.text()).toContain('4');
    expect(wrapper.text()).toContain('3');
  });

  it('muestra un aviso de error con boton de reintentar cuando el fetch falla', async () => {
    fetchTodas.mockRejectedValueOnce(new Error('500'));
    const wrapper = shallowMount(TodasTab);
    await flushPromises();

    expect(wrapper.text()).toContain('HELIC3_INDICADORES.ERROR');
    const reintentar = wrapper
      .findAllComponents(Button)
      .find(boton => boton.props('label') === 'HELIC3_INDICADORES.RETRY');
    expect(reintentar).toBeTruthy();
  });
});
