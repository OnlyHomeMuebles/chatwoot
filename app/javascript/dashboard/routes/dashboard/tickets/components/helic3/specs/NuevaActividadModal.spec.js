import { shallowMount, flushPromises } from '@vue/test-utils';
import NuevaActividadModal from '../NuevaActividadModal.vue';

const dispatch = vi.fn();
const useAlert = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: m => useAlert(m) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (k, args) => (args ? `${k} ${JSON.stringify(args)}` : k),
  }),
}));

const dialogOpen = vi.fn();
const dialogClose = vi.fn();
const DialogStub = {
  name: 'Dialog',
  props: ['disableConfirmButton'],
  emits: ['confirm'],
  template: '<div><slot /></div>',
  methods: { open: dialogOpen, close: dialogClose },
};

const montar = () =>
  shallowMount(NuevaActividadModal, {
    props: { ticketId: 7 },
    global: { stubs: { Dialog: DialogStub } },
  });

const llenar = async (wrapper, titulo, detalle) => {
  await wrapper
    .findComponent('[data-testid="input-titulo"]')
    .vm.$emit('update:modelValue', titulo);
  await wrapper
    .findComponent('[data-testid="input-detalle"]')
    .vm.$emit('update:modelValue', detalle);
};

beforeEach(() => {
  dispatch.mockReset();
  dispatch.mockResolvedValue();
  useAlert.mockClear();
  dialogOpen.mockClear();
  dialogClose.mockClear();
});

describe('NuevaActividadModal (ACT-01)', () => {
  it('Agregar queda deshabilitado mientras falte el titulo o el detalle', async () => {
    const wrapper = montar();
    wrapper.vm.open();
    const dialog = () => wrapper.findComponent(DialogStub);

    expect(dialog().props('disableConfirmButton')).toBe(true);
    await llenar(wrapper, 'Llamada', '   ');
    expect(dialog().props('disableConfirmButton')).toBe(true);
    await llenar(wrapper, 'Llamada', 'Agenda visita');
    expect(dialog().props('disableConfirmButton')).toBe(false);
  });

  it('un titulo de mas de 120 caracteres no se puede guardar', async () => {
    const wrapper = montar();
    wrapper.vm.open();
    await llenar(wrapper, 'a'.repeat(121), 'Agenda visita');

    expect(wrapper.vm.puedeAgregar).toBe(false);
    expect(wrapper.text()).toContain(
      'TICKETS.ACTIVIDAD.CHAR_COUNT {"n":121,"max":120}'
    );
  });

  it('al agregar guarda titulo y detalle recortados, recarga el expediente y cierra', async () => {
    const wrapper = montar();
    wrapper.vm.open();
    await llenar(wrapper, '  Llamada al cliente ', ' Agenda visita el jueves ');

    await wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(dispatch).toHaveBeenNthCalledWith(1, 'tickets/crearActividad', {
      ticketId: 7,
      actividad: {
        titulo: 'Llamada al cliente',
        detalle: 'Agenda visita el jueves',
      },
    });
    expect(dispatch).toHaveBeenNthCalledWith(2, 'pqrInbox/fetchOne', 7);
    expect(useAlert).toHaveBeenCalledWith('TICKETS.ACTIVIDAD.SAVED');
    expect(dialogClose).toHaveBeenCalled();
  });

  it('sin titulo o detalle, Enter no envia nada', async () => {
    const wrapper = montar();
    wrapper.vm.open();

    await wrapper.findComponent(DialogStub).vm.$emit('confirm');

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('si el servidor rechaza, muestra el error en el modal y no lo cierra', async () => {
    dispatch.mockRejectedValueOnce({
      response: { data: { message: 'Titulo no puede estar en blanco' } },
    });
    const wrapper = montar();
    wrapper.vm.open();
    await llenar(wrapper, 'Llamada', 'Agenda visita');

    await wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(wrapper.find('[data-testid="error"]').text()).toBe(
      'Titulo no puede estar en blanco'
    );
    expect(dialogClose).not.toHaveBeenCalled();
  });

  it('al abrir de nuevo arranca vacio', async () => {
    const wrapper = montar();
    wrapper.vm.open();
    await llenar(wrapper, 'Llamada', 'Agenda visita');

    wrapper.vm.open();
    await flushPromises();

    expect(wrapper.vm.puedeAgregar).toBe(false);
    expect(dialogOpen).toHaveBeenCalledTimes(2);
  });
});
