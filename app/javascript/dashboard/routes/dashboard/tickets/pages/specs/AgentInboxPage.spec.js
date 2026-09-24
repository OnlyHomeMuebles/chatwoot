import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import AgentInboxPage from '../AgentInboxPage.vue';

const recordsRef = ref([]);
const metaRef = ref({ count: 0, perPage: 25, metricas: null });
const dispatch = vi.fn().mockResolvedValue();
const push = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'pqrInbox/getRecords') return recordsRef;
    if (getter === 'pqrInbox/getMeta') return metaRef;
    return ref({ isFetching: false }); // pqrInbox/getUIFlags
  },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
  }),
}));

const filaConConversacion = {
  id: 1,
  title: 'Silla dañada',
  numero_radicado: '#4',
  conversation_display_id: 12,
  cliente: { nombre: 'Juan Pérez', documento: '123' },
  tipo: { nombre: 'Reclamo' },
  motivo_pqr: { nombre: 'Garantía de producto' },
  categoria: { nombre: 'Garantía' },
  etapa: { codigo: 'nueva', nombre: 'Nueva' },
  garantia: null,
};

describe('AgentInboxPage.vue — bandeja de supervisión del agente (BAN-02)', () => {
  beforeEach(() => {
    dispatch.mockClear();
    push.mockClear();
    recordsRef.value = [];
    metaRef.value = { count: 0, perPage: 25, metricas: null };
  });

  it('pide la bandeja al montar, fija origen=agente sin exponer un toggle', () => {
    shallowMount(AgentInboxPage);

    expect(dispatch).toHaveBeenCalledWith('pqrInbox/fetch', {
      origen: 'agente',
      page: 1,
    });
  });

  it('un clic en una fila con conversacion abre la conversacion real de Chatwoot', async () => {
    recordsRef.value = [filaConConversacion];
    const wrapper = shallowMount(AgentInboxPage);

    await wrapper.find('tbody tr').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: '1', conversation_id: 12 },
    });
  });

  it('un clic en una fila SIN conversacion asociada no navega a ningún lado', async () => {
    recordsRef.value = [
      { ...filaConConversacion, conversation_display_id: null },
    ];
    const wrapper = shallowMount(AgentInboxPage);

    await wrapper.find('tbody tr').trigger('click');

    expect(push).not.toHaveBeenCalled();
  });

  it('muestra el estado vacío cuando el agente no ha radicado nada', () => {
    const wrapper = shallowMount(AgentInboxPage);

    expect(wrapper.text()).toContain('TICKETS.AGENT_INBOX.EMPTY');
  });
});
