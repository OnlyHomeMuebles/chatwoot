import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import FormatosPanel from '../FormatosPanel.vue';
import FormatoCard from '../FormatoCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const formatosRef = ref([
  {
    id: 1,
    codigo: 'visita_tecnica',
    nombre: 'Visita',
    activa_id: 10,
    versiones: [
      { id: 10, version: 1, estado: 'activa', marcadores: ['CLIENTE'] },
    ],
  },
]);
const marcadoresRef = ref({
  CLIENTE: { descripcion: 'Nombre del cliente', ejemplo: 'Ana' },
});
const uiFlagsRef = ref({ isFetching: false, isSaving: false });
const roleRef = ref('administrator');
const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'helic3Formatos/getFormatos') return formatosRef;
    if (getter === 'helic3Formatos/getMarcadores') return marcadoresRef;
    if (getter === 'helic3Formatos/getUIFlags') return uiFlagsRef;
    return roleRef; // getCurrentRole
  },
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: clave => clave }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const montar = () => shallowMount(FormatosPanel);

beforeEach(() => {
  dispatch.mockClear();
  dispatch.mockResolvedValue();
});

describe('FormatosPanel', () => {
  it('carga formatos y marcadores al montar', () => {
    montar();
    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/fetchFormatos');
    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/fetchMarcadores');
  });

  it('pinta una tarjeta por formato', () => {
    const wrapper = montar();
    expect(wrapper.findAllComponents(FormatoCard)).toHaveLength(1);
  });

  it('copiar un marcador escribe {{NOMBRE}} en el portapapeles', async () => {
    const writeText = vi.fn().mockResolvedValue();
    Object.assign(navigator, { clipboard: { writeText } });
    const wrapper = montar();
    await wrapper.find('[data-testid="copiar-CLIENTE"]').trigger('click');
    expect(writeText).toHaveBeenCalledWith('{{CLIENTE}}');
  });

  it('subir despacha la accion del store', async () => {
    const wrapper = montar();
    wrapper.findComponent(FormatoCard).vm.$emit('subir', {
      formato: formatosRef.value[0],
      archivo: new File(['x'], 'p.docx'),
    });
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith(
      'helic3Formatos/subirPlantilla',
      expect.objectContaining({ formatoId: 1 })
    );
  });

  it('crear un formato despacha crearFormato con el código derivado del nombre [FMT-06]', async () => {
    const wrapper = shallowMount(FormatosPanel, {
      global: { renderStubDefaultSlot: true },
    });
    await wrapper
      .find('[data-testid="input-nombre"]')
      .setValue('Acta Especial');
    await wrapper.findComponent(Dialog).vm.$emit('confirm');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/crearFormato', {
      nombre: 'Acta Especial',
      codigo: 'acta_especial',
    });
  });

  it('desactivar un formato despacha desactivarFormato [FMT-06]', async () => {
    const wrapper = montar();
    wrapper.findComponent(FormatoCard).vm.$emit('desactivar', 1);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'helic3Formatos/desactivarFormato',
      1
    );
  });

  it('reactivar un formato despacha reactivarFormato [FMT-06]', async () => {
    const wrapper = montar();
    wrapper.findComponent(FormatoCard).vm.$emit('reactivar', 1);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/reactivarFormato', 1);
  });

  it('un fallo al previsualizar no rompe el panel (Review Focus 4)', async () => {
    dispatch.mockImplementation(accion =>
      accion === 'helic3Formatos/vistaPrevia'
        ? Promise.reject(new Error('x'))
        : Promise.resolve()
    );
    const wrapper = montar();
    wrapper.findComponent(FormatoCard).vm.$emit('previsualizar', 10);
    await flushPromises();
    expect(wrapper.exists()).toBe(true);
    expect(wrapper.find('[data-testid="iframe-previa"]').exists()).toBe(false);
  });
});
