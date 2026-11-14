import { shallowMount, flushPromises } from '@vue/test-utils';
import GenerarFormatoModal from '../GenerarFormatoModal.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import GenerarFormatoAPI from 'dashboard/api/helic3/generarFormato';

const dispatch = vi.fn().mockResolvedValue();
const alert = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

// el cliente API se mockea: probamos la logica del modal (seleccion, faltantes,
// generar), no las llamadas HTTP reales.
vi.mock('dashboard/api/helic3/generarFormato', () => ({
  default: {
    listar: vi.fn(),
    vistaPrevia: vi.fn(),
    generar: vi.fn(),
  },
}));

const MARCADORES_EDITABLES = {
  PRODUCTO: { etiqueta: 'Nombre del producto', tipo: 'texto' },
  PRODUCTO_DESCRIPCION: { etiqueta: 'Descripción', tipo: 'area' },
  PRODUCTO_NUEVO: { etiqueta: 'Producto nuevo', tipo: 'texto' },
};

const respuestaListar = {
  data: {
    marcadores_editables: MARCADORES_EDITABLES,
    formatos: [
      {
        id: 1,
        codigo: 'visita_tecnica',
        nombre: 'No. 3 · Visita de técnico',
        plantilla_activa: {
          id: 10,
          version: 1,
          marcadores: ['CLIENTE', 'CEDULA'],
        },
      },
      {
        id: 2,
        codigo: 'recoleccion_productos',
        nombre: 'No. 5 · Recolección',
        plantilla_activa: null,
      },
      {
        id: 3,
        codigo: 'cambio_producto',
        nombre: 'No. 4 · Cambio de producto',
        plantilla_activa: {
          id: 11,
          version: 1,
          marcadores: ['PRODUCTO', 'PRODUCTO_NUEVO'],
        },
      },
    ],
    items: [
      {
        id: 9,
        producto_nombre: 'Sofá',
        proceso_codigo: 'visita_tecnica',
        formato_sugerido_id: 1,
        marcadores_vacios: ['CEDULA'],
        ultimos_valores: {},
      },
    ],
  },
};

const montarYAbrir = async (data = respuestaListar.data) => {
  GenerarFormatoAPI.listar.mockResolvedValue({ data });
  const wrapper = shallowMount(GenerarFormatoModal, {
    props: { ticketId: 7 },
    // el contenido del formulario vive en el slot del Dialog (stub); sin esto
    // shallowMount no lo renderiza y no habria data-testid que consultar.
    global: { renderStubDefaultSlot: true },
  });
  await wrapper.vm.open();
  await flushPromises();
  return wrapper;
};

beforeEach(() => {
  dispatch.mockClear();
  alert.mockClear();
  GenerarFormatoAPI.generar.mockClear();
  GenerarFormatoAPI.generar.mockResolvedValue({ data: { id: 99 } });
});

describe('GenerarFormatoModal.vue (FMT-04)', () => {
  it('al abrir carga los formatos y preselecciona el sugerido', async () => {
    const wrapper = await montarYAbrir();

    expect(GenerarFormatoAPI.listar).toHaveBeenCalledWith(7);
    // el formato sugerido (id 1, con plantilla) queda marcado
    expect(wrapper.find('[data-testid="badge-sugerido"]').exists()).toBe(true);
  });

  it('deshabilita el formato sin plantilla activa', async () => {
    const wrapper = await montarYAbrir();

    const sinPlantilla = wrapper.find('[data-testid="formato-2"]');
    expect(sinPlantilla.attributes('disabled')).toBeDefined();
  });

  it('calcula faltantes como la intersección de marcadores usados y vacíos', async () => {
    const wrapper = await montarYAbrir();

    // plantilla usa CLIENTE+CEDULA; el ítem tiene CEDULA vacío -> falta CEDULA
    const faltantes = wrapper.find('[data-testid="faltantes"]');
    expect(faltantes.exists()).toBe(true);
    expect(faltantes.text()).toContain('CEDULA');
    expect(faltantes.text()).not.toContain('CLIENTE');
  });

  it('al confirmar genera y refresca los documentos del caso', async () => {
    const wrapper = await montarYAbrir();

    await wrapper.findComponent(Dialog).vm.$emit('confirm');
    await flushPromises();

    expect(GenerarFormatoAPI.generar).toHaveBeenCalledWith(7, {
      formatoId: 1,
      itemId: 9,
      valoresProducto: {},
    });
    expect(dispatch).toHaveBeenCalledWith('pqrInbox/fetchDocumentos', 7);
  });

  it('pinta una casilla por cada marcador editable que usa la plantilla [FMT-07]', async () => {
    const wrapper = await montarYAbrir();
    await wrapper.find('[data-testid="formato-3"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="campo-PRODUCTO"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="campo-PRODUCTO_NUEVO"]').exists()).toBe(true);
    // la plantilla de cambio no usa descripción, así que esa casilla no aparece
    expect(wrapper.find('[data-testid="campo-PRODUCTO_DESCRIPCION"]').exists()).toBe(false);
  });

  it('prellena el producto original con el nombre del ítem [FMT-07]', async () => {
    const wrapper = await montarYAbrir();
    await wrapper.find('[data-testid="formato-3"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="campo-PRODUCTO"]').element.value).toBe('Sofá');
  });

  it('prellena con los últimos valores de una generación previa [FMT-07]', async () => {
    const wrapper = await montarYAbrir({
      ...respuestaListar.data,
      items: [
        {
          ...respuestaListar.data.items[0],
          ultimos_valores: { cambio_producto: { PRODUCTO: 'Mesa', PRODUCTO_NUEVO: 'Mesa XL' } },
        },
      ],
    });
    await wrapper.find('[data-testid="formato-3"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="campo-PRODUCTO"]').element.value).toBe('Mesa');
    expect(wrapper.find('[data-testid="campo-PRODUCTO_NUEVO"]').element.value).toBe('Mesa XL');
  });

  it('deshabilita generar mientras una casilla obligatoria esté vacía [FMT-07]', async () => {
    const wrapper = await montarYAbrir();
    await wrapper.find('[data-testid="formato-3"]').trigger('click');
    await flushPromises();

    // PRODUCTO prellenado pero PRODUCTO_NUEVO vacío -> no se puede generar
    expect(wrapper.findComponent(Dialog).props('disableConfirmButton')).toBe(true);

    await wrapper.find('[data-testid="campo-PRODUCTO_NUEVO"]').setValue('Sofá Turín');
    expect(wrapper.findComponent(Dialog).props('disableConfirmButton')).toBe(false);
  });

  it('deja previsualizar aunque falte una casilla obligatoria [FMT-07]', async () => {
    const wrapper = await montarYAbrir();
    await wrapper.find('[data-testid="formato-3"]').trigger('click');
    await flushPromises();

    // PRODUCTO_NUEVO vacío: generar bloqueado, pero la vista previa SÍ disponible
    expect(wrapper.findComponent(Dialog).props('disableConfirmButton')).toBe(true);
    expect(wrapper.find('[data-testid="btn-previa"]').exists()).toBe(true);
  });

  it('envía lo escrito en las casillas al generar [FMT-07]', async () => {
    const wrapper = await montarYAbrir();
    await wrapper.find('[data-testid="formato-3"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="campo-PRODUCTO_NUEVO"]').setValue('Sofá Turín');

    await wrapper.findComponent(Dialog).vm.$emit('confirm');
    await flushPromises();

    expect(GenerarFormatoAPI.generar).toHaveBeenCalledWith(7, {
      formatoId: 3,
      itemId: 9,
      valoresProducto: { PRODUCTO: 'Sofá', PRODUCTO_NUEVO: 'Sofá Turín' },
    });
  });

  it('al fallar la generación muestra el mensaje del servidor [N3]', async () => {
    GenerarFormatoAPI.generar.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'el formato no tiene una plantilla activa' },
      },
    });
    const wrapper = await montarYAbrir();

    await wrapper.findComponent(Dialog).vm.$emit('confirm');
    await flushPromises();

    expect(alert).toHaveBeenCalledWith(
      'el formato no tiene una plantilla activa'
    );
  });
});
