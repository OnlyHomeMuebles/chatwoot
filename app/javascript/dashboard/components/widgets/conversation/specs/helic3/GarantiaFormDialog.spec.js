import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import GarantiaFormDialog from '../../GarantiaFormDialog.vue';

const catalogosRef = ref({
  coberturas_ciudad: [{ id: 1, nombre: 'Armenia' }],
  motivos_garantia: [],
  detalles_tipificados: [],
});
const uiFlagsRef = ref({ isUpdating: false });

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: getter =>
    getter === 'tickets/getUIFlags' ? uiFlagsRef : catalogosRef,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

// Dialog stub con open/close para que `dialogRef.value.open()` no falle en shallowMount.
const DialogStub = {
  template: '<div><slot /></div>',
  methods: { open() {}, close() {} },
};

const montar = () =>
  shallowMount(GarantiaFormDialog, { global: { stubs: { Dialog: DialogStub } } });

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
    expect(vm.productos.map(p => p.producto_referencia)).toEqual(['MIL-200', 'CER-050']);
  });

  it('sin lista de productos, cae al producto unico (compat chat / MAN-03)', () => {
    const vm = montar().vm;

    vm.open({ id: 1 }, 10, { producto_nombre: 'Mesa', producto_referencia: 'M-1' });

    expect(vm.productos).toHaveLength(1);
    expect(vm.productos[0].producto_nombre).toBe('Mesa');
  });
});
