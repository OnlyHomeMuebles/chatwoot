import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import ConversationTickets from '../ConversationTickets.vue';

// Un solo dispatch espiado para verificar que el panel vuelve a pedir la lista.
const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'tickets/getCatalogos') return ref({ resultados: [] });
    return ref([]); // tickets/getTickets
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('ConversationTickets.vue — refresco al cambiar de conversación (CTR-03)', () => {
  beforeEach(() => dispatch.mockClear());

  // El panel NO se remonta al cambiar de chat (v-show, sin :key): solo le cambia el
  // prop. Este test falla si alguien quita el watch de conversationId y el panel
  // deja de refrescarse, que es justo el gotcha que CTR-03 arregló.
  it('vuelve a pedir la lista (tickets/get) al cambiar de conversación', async () => {
    const wrapper = shallowMount(ConversationTickets, {
      props: { conversationId: 1 },
    });
    await flushPromises();
    dispatch.mockClear(); // descartamos el fetch inicial de onMounted

    await wrapper.setProps({ conversationId: 2 });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('tickets/get');
  });
});
