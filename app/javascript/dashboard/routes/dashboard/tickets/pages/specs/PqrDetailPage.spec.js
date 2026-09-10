import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import PqrDetailPage from '../PqrDetailPage.vue';

// Estado controlable del expediente actual (lo que devuelve pqrInbox/getCurrent).
const expedienteRef = ref(null);

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue() }),
  useMapGetter: getter => {
    if (getter === 'pqrInbox/getUIFlags') return ref({ isFetchingItem: false });
    if (getter === 'agents/getAgents') return ref([]);
    return expedienteRef; // pqrInbox/getCurrent
  },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
  }),
}));

const expedienteBase = {
  id: 7,
  title: 'Sofá rayado',
  numero_radicado: '#3',
  status: 'open',
};

const conGarantia = {
  ...expedienteBase,
  garantia: {
    numero_radicado: '1204',
    presupuesto_dias_habiles: 30,
    proceso_visible: { nombre: 'Visita técnica' },
    cobertura_ciudad: { nombre: 'Manizales', tecnico_propio: true },
    presupuesto: { consumidos: 3, saldo: 27, semaforo: 'verde' },
    items: [
      {
        id: 9,
        producto_nombre: 'Sofá Modular',
        proceso: { nombre: 'Visita técnica' },
      },
    ],
  },
};

const montar = () => shallowMount(PqrDetailPage, { props: { id: 7 } });

describe('PqrDetailPage.vue — bloque de garantía (DET-01)', () => {
  it('pinta el bloque de garantía cuando viene en el payload', () => {
    expedienteRef.value = conGarantia;

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-garantia"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('1204');
  });

  it('NO pinta el bloque de garantía cuando garantia es null', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-garantia"]').exists()).toBe(
      false
    );
  });
});
