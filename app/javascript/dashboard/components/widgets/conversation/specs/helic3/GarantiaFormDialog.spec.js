import { shallowMount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import GarantiaFormDialog from '../../GarantiaFormDialog.vue';

const catalogosRef = ref({
  coberturas_ciudad: [
    {
      id: 1,
      nombre: 'Armenia',
      tecnico_propio: true,
      proceso_inicial_nombre: 'Visita técnica',
    },
  ],
  motivos_garantia: [{ id: 7, nombre: 'Defecto de fabricación' }],
  detalles_tipificados: [{ id: 3, nombre: 'Producto mal pintado' }],
  resultados: [{ id: 10, nombre: 'Aplica garantía', abre_garantia: true }],
});
const uiFlagsRef = ref({ isUpdating: false });
const dispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter =>
    getter === 'tickets/getUIFlags' ? uiFlagsRef : catalogosRef,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

// Dialog stub con open/close para que `dialogRef.value.open()` no falle en shallowMount.
const DialogStub = {
  name: 'Dialog',
  props: ['disableConfirmButton'],
  emits: ['confirm'],
  template: '<div><slot /></div>',
  methods: { open() {}, close() {} },
};

const montar = () =>
  shallowMount(GarantiaFormDialog, {
    global: { stubs: { Dialog: DialogStub } },
  });

beforeEach(() => dispatch.mockReset());

describe('GarantiaFormDialog (ERP-15)', () => {
  it('abre con una fila por producto de la ficha (prefill.productos)', () => {
    const vm = montar().vm;

    vm.open({ id: 1 }, 10, {
      productos: [
        { nombre: 'Puerta Milano', referencia: 'MIL-200', fuente: 'erp' },
        { nombre: 'Cerradura Premium', referencia: 'CER-050', fuente: 'erp' },
      ],
      ciudad_nombre: 'Armenia',
    });

    expect(vm.productos).toHaveLength(2);
    expect(vm.productos.map(p => p.producto_nombre)).toEqual([
      'Puerta Milano',
      'Cerradura Premium',
    ]);
    expect(vm.productos.map(p => p.producto_referencia)).toEqual([
      'MIL-200',
      'CER-050',
    ]);
  });

  it('sin lista de productos, cae al producto unico (compat chat / MAN-03)', () => {
    const vm = montar().vm;

    vm.open({ id: 1 }, 10, {
      producto_nombre: 'Mesa',
      producto_referencia: 'M-1',
    });

    expect(vm.productos).toHaveLength(1);
    expect(vm.productos[0].producto_nombre).toBe('Mesa');
  });
});

describe('GarantiaFormDialog (GAR-06)', () => {
  it('no pide el detalle tipificado: solo lo muestra', async () => {
    const wrapper = montar();

    wrapper.vm.open({ id: 1 }, 10, {
      producto_nombre: 'Mesa',
      detalle_nombre: 'Producto mal pintado',
    });
    await nextTick();

    expect(wrapper.find('[data-testid="select-detalle"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="detalle-reportado"]').exists()).toBe(
      true
    );
  });

  it('el payload no envia detalle_tipificado_id', async () => {
    const wrapper = montar();
    wrapper.vm.open({ id: 5 }, 10, {
      producto_nombre: 'Mesa',
      ciudad_nombre: 'Armenia',
    });
    wrapper.vm.productos[0].motivo_garantia_id = 7;
    await nextTick();

    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await nextTick();

    expect(dispatch).toHaveBeenCalledWith('tickets/resolver', {
      id: 5,
      resultadoId: 10,
      garantia: {
        cobertura_ciudad_id: 1,
        items: [
          {
            producto_nombre: 'Mesa',
            producto_referencia: '',
            motivo_garantia_id: 7,
          },
        ],
      },
    });
  });

  it('confirmar queda deshabilitado sin motivo y dice que falta', async () => {
    const wrapper = montar();
    wrapper.vm.open({ id: 1 }, 10, {
      producto_nombre: 'Mesa',
      ciudad_nombre: 'Armenia',
    });
    await nextTick();

    expect(wrapper.vm.puedeConfirmar).toBe(false);
    expect(wrapper.vm.faltante).toBe('TICKETS.WARRANTY.FORM.MISSING_MOTIVE');
    expect(
      wrapper.findComponent(DialogStub).props('disableConfirmButton')
    ).toBe(true);

    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('los productos precargados se muestran en solo lectura', async () => {
    const wrapper = montar();
    wrapper.vm.open({ id: 1 }, 10, {
      productos: [{ nombre: 'Puerta Milano', referencia: 'MIL-200' }],
    });
    await nextTick();

    expect(wrapper.find('[data-testid="producto-nombre"]').text()).toContain(
      'Puerta Milano'
    );
    expect(wrapper.find('[data-testid="input-nombre"]').exists()).toBe(false);
  });

  it('desde el chat sin datos abre una tarjeta editable vacia', async () => {
    const wrapper = montar();
    wrapper.vm.open({ id: 1 }, 10);
    await nextTick();

    expect(wrapper.vm.productos).toHaveLength(1);
    expect(wrapper.find('[data-testid="input-nombre"]').exists()).toBe(true);
    expect(wrapper.vm.faltante).toBe('TICKETS.WARRANTY.FORM.MISSING_CITY');
  });
});
