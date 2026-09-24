import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import PqrDetailPage from '../PqrDetailPage.vue';

// Estado controlable del expediente actual (lo que devuelve pqrInbox/getCurrent).
const expedienteRef = ref(null);
const documentosRef = ref([]);
const uiFlagsRef = ref({ isFetchingItem: false, isUploadingDocumento: false });
const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'pqrInbox/getUIFlags') return uiFlagsRef;
    if (getter === 'agents/getAgents') return ref([]);
    if (getter === 'pqrInbox/getDocumentos') return documentosRef;
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

beforeEach(() => {
  documentosRef.value = [];
  uiFlagsRef.value = { isFetchingItem: false, isUploadingDocumento: false };
  dispatch.mockClear();
});

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

describe('PqrDetailPage.vue — documentos del expediente (EVI-03)', () => {
  it('pide el archivo documental al montar', async () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };

    montar();
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('pqrInbox/fetchDocumentos', 7);
  });

  it('muestra el estado vacío cuando no hay documentos ni formato de garantía', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    documentosRef.value = [];

    const wrapper = montar();

    expect(wrapper.text()).toContain('TICKETS.DETAIL.DOC_EMPTY');
  });

  it('lista los documentos reales, con remitente y sin el estado vacío', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    documentosRef.value = [
      {
        id: 1,
        clase: 'evidencia',
        origen: 'cliente',
        titulo: 'factura.jpg',
        tipo_archivo: 'image/jpeg',
        url: 'https://x.test/factura.jpg',
        ocurrido_at: '2026-09-20T10:00:00Z',
        remitente: { nombre: 'Juan Pérez', user_id: null },
      },
    ];

    const wrapper = montar();

    expect(wrapper.text()).toContain('factura.jpg');
    expect(wrapper.text()).toContain('Juan Pérez');
    expect(wrapper.text()).not.toContain('TICKETS.DETAIL.DOC_EMPTY');
  });

  it('un documento del agente sin remitente muestra la etiqueta de agente IA', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    documentosRef.value = [
      {
        id: 2,
        clase: 'evidencia',
        origen: 'agente',
        titulo: 'foto.png',
        tipo_archivo: 'image/png',
        url: 'https://x.test/foto.png',
        ocurrido_at: '2026-09-20T10:00:00Z',
        remitente: { nombre: null, user_id: null },
      },
    ];

    const wrapper = montar();

    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_BY_AGENT');
  });
});

describe('PqrDetailPage.vue — actividad desde la bitácora real (EVI-03, cobro de EVT-01)', () => {
  it('pinta cada evento de la bitacora con su titulo y su autor', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [
        {
          id: 1,
          tipo: 'radicada',
          origen: 'humano',
          actor: { id: 3, name: 'Ana Torres' },
          created_at: '2026-09-19T09:00:00Z',
        },
        {
          id: 2,
          tipo: 'evidencia_adjuntada',
          origen: 'agente',
          actor: null,
          created_at: '2026-09-19T10:00:00Z',
        },
      ],
    };

    const wrapper = montar();

    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_FILED');
    expect(wrapper.text()).toContain('Ana Torres');
    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_EVIDENCIA_ADJUNTADA');
    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_BY_AGENT');
  });

  it('no pinta la tarjeta de actividad cuando el expediente no tiene eventos', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null, eventos: [] };

    const wrapper = montar();

    expect(wrapper.text()).not.toContain('TICKETS.DETAIL.ACTIVITY');
  });
});
