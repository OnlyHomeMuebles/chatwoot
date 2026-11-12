import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import ConversationTickets from '../ConversationTickets.vue';
import Select from 'dashboard/components-next/select/Select.vue';

// Un solo dispatch espiado para verificar que el panel vuelve a pedir la lista.
const dispatch = vi.fn().mockResolvedValue();
const ticketsRef = ref([]);
const catalogosRef = ref({ resultados: [] });

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'tickets/getCatalogos') return catalogosRef;
    return ticketsRef; // tickets/getTickets
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

describe('ConversationTickets.vue — detalle tipificado en Datos del caso (GAR-06)', () => {
  beforeEach(() => {
    dispatch.mockClear();
    catalogosRef.value = {
      resultados: [],
      detalles_tipificados: [{ id: 3, nombre: 'Producto mal pintado' }],
    };
    ticketsRef.value = [
      { id: 5, conversation_display_id: 1, status: 'open', datos: {} },
    ];
  });

  afterEach(() => {
    ticketsRef.value = [];
    catalogosRef.value = { resultados: [] };
  });

  // La garantia no se abre sin detalle: se tiene que poder completar desde el chat.
  it('elegir el detalle lo guarda en la ficha', async () => {
    const wrapper = shallowMount(ConversationTickets, {
      props: { conversationId: 1 },
    });
    await flushPromises();
    dispatch.mockClear();

    const selectDetalle = wrapper.find('[data-testid="select-detalle-ficha"]');
    await wrapper
      .findAllComponents(Select)
      .find(s => s.element === selectDetalle.element)
      .vm.$emit('update:modelValue', 3);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('tickets/registrarDatos', {
      id: 5,
      datos: { detalle_tipificado_id: 3 },
    });
  });
});
