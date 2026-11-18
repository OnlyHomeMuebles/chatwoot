import { shallowMount, flushPromises } from '@vue/test-utils';
import FinalizarGarantiaModal from '../../helic3/FinalizarGarantiaModal.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (k, args) => (args ? `${k} ${JSON.stringify(args)}` : k),
  }),
}));

const dialogOpen = vi.fn();
const dialogClose = vi.fn();
// el Dialog real emite 'close' cuando se cierra (cancelar, Esc o close()); el stub
// lo replica para probar el gate exito/onCancel.
const DialogStub = {
  name: 'Dialog',
  props: ['disableConfirmButton'],
  emits: ['confirm', 'close'],
  template: '<div><slot /></div>',
  methods: {
    open: dialogOpen,
    close() {
      dialogClose();
      this.$emit('close');
    },
  },
};

const montar = () =>
  shallowMount(FinalizarGarantiaModal, {
    global: { stubs: { Dialog: DialogStub } },
  });

const escribir = (wrapper, texto) =>
  wrapper
    .findComponent('[data-testid="input-observacion"]')
    .vm.$emit('update:modelValue', texto);

const dialog = wrapper => wrapper.findComponent(DialogStub);

beforeEach(() => {
  dialogOpen.mockClear();
  dialogClose.mockClear();
});

describe('FinalizarGarantiaModal (GAR-08)', () => {
  it('Finalizar queda deshabilitado sin texto y habilitado con texto (CA#1)', async () => {
    const wrapper = montar();
    wrapper.vm.open({ onConfirm: vi.fn() });

    expect(dialog(wrapper).props('disableConfirmButton')).toBe(true);
    await escribir(wrapper, '   ');
    expect(dialog(wrapper).props('disableConfirmButton')).toBe(true);
    await escribir(wrapper, 'Se reparó y se entregó.');
    expect(dialog(wrapper).props('disableConfirmButton')).toBe(false);
  });

  it('un texto de más de 1000 caracteres no se puede confirmar', async () => {
    const wrapper = montar();
    wrapper.vm.open({ onConfirm: vi.fn() });
    await escribir(wrapper, 'a'.repeat(1001));

    expect(dialog(wrapper).props('disableConfirmButton')).toBe(true);
  });

  it('al confirmar llama onConfirm con el texto recortado y cierra', async () => {
    const onConfirm = vi.fn().mockResolvedValue();
    const wrapper = montar();
    wrapper.vm.open({ onConfirm });
    await escribir(wrapper, '  Entregado y firmado.  ');

    await dialog(wrapper).vm.$emit('confirm');
    await flushPromises();

    expect(onConfirm).toHaveBeenCalledWith('Entregado y firmado.');
    expect(dialogClose).toHaveBeenCalled();
  });

  it('sin texto, Enter (confirm) no llama onConfirm', async () => {
    const onConfirm = vi.fn();
    const wrapper = montar();
    wrapper.vm.open({ onConfirm });

    await dialog(wrapper).vm.$emit('confirm');

    expect(onConfirm).not.toHaveBeenCalled();
  });

  it('si onConfirm rechaza (p.ej. 422), muestra el error y no cierra', async () => {
    const onConfirm = vi.fn().mockRejectedValueOnce({
      response: { data: { error: 'La observación es obligatoria' } },
    });
    const wrapper = montar();
    wrapper.vm.open({ onConfirm });
    await escribir(wrapper, 'Texto');

    await dialog(wrapper).vm.$emit('confirm');
    await flushPromises();

    expect(wrapper.find('[data-testid="error"]').text()).toBe(
      'La observación es obligatoria'
    );
    expect(dialogClose).not.toHaveBeenCalled();
  });

  it('cancelar (cerrar sin confirmar) ejecuta onCancel (CA#3)', async () => {
    const onCancel = vi.fn();
    const wrapper = montar();
    wrapper.vm.open({ onConfirm: vi.fn(), onCancel });

    await dialog(wrapper).vm.$emit('close');

    expect(onCancel).toHaveBeenCalled();
  });

  it('tras un confirm exitoso, cerrar NO vuelve a disparar onCancel', async () => {
    const onCancel = vi.fn();
    const wrapper = montar();
    wrapper.vm.open({ onConfirm: vi.fn().mockResolvedValue(), onCancel });
    await escribir(wrapper, 'Listo');

    await dialog(wrapper).vm.$emit('confirm');
    await flushPromises();

    // el confirm exitoso ya cerró el dialog (emitió close); onCancel no debe correr
    expect(onCancel).not.toHaveBeenCalled();
  });

  it('abrir con texto precargado (editar) lo deja listo para confirmar', async () => {
    const wrapper = montar();
    wrapper.vm.open({ texto: 'Observación previa', onConfirm: vi.fn() });
    await flushPromises();

    expect(dialog(wrapper).props('disableConfirmButton')).toBe(false);
  });
});
