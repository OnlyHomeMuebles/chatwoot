import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import CorreosPanel from '../CorreosPanel.vue';
import PlantillaCorreoCard from '../PlantillaCorreoCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const plantillasRef = ref([
  {
    id: 1,
    disparador: 'proceso_garantia',
    proceso_garantia_id: 10,
    proceso_nombre: 'Visita técnica',
    asunto: 'Hola {{CLIENTE}}',
    cuerpo: 'x',
    activo: true,
  },
]);
const marcadoresRef = ref({
  CLIENTE: { descripcion: 'Nombre del cliente', ejemplo: 'Ana' },
});
const procesosGarantia = [
  { id: 10, nombre: 'Visita técnica', activo: true },
  { id: 20, nombre: 'Garantía negada', activo: true },
  { id: 30, nombre: 'Proceso inactivo', activo: false },
];
const roleRef = ref('administrator');
const dispatch = vi.fn().mockResolvedValue();
const alert = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'helic3Correos/getPlantillas') return plantillasRef;
    if (getter === 'helic3Formatos/getMarcadores') return marcadoresRef;
    if (getter === 'pqrCatalogos/getCatalogo') {
      return ref(tipo =>
        tipo === 'procesos_garantia' ? procesosGarantia : []
      );
    }
    return roleRef; // getCurrentRole
  },
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: clave => clave }) }));
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

const montar = () =>
  shallowMount(CorreosPanel, { global: { renderStubDefaultSlot: true } });

beforeEach(() => {
  dispatch.mockClear();
  dispatch.mockResolvedValue();
  alert.mockClear();
});

describe('CorreosPanel', () => {
  it('carga plantillas, marcadores y el catalogo de procesos al montar', () => {
    montar();
    expect(dispatch).toHaveBeenCalledWith('helic3Correos/fetchPlantillas');
    expect(dispatch).toHaveBeenCalledWith('helic3Formatos/fetchMarcadores');
    expect(dispatch).toHaveBeenCalledWith(
      'pqrCatalogos/fetchCatalogo',
      'procesos_garantia'
    );
  });

  it('pinta una tarjeta por plantilla', () => {
    const wrapper = montar();
    expect(wrapper.findAllComponents(PlantillaCorreoCard)).toHaveLength(1);
  });

  it('guardar despacha actualizarPlantilla con los datos emitidos', async () => {
    const wrapper = montar();
    wrapper.findComponent(PlantillaCorreoCard).vm.$emit('guardar', {
      id: 1,
      data: { asunto: 'Nuevo', cuerpo: 'x' },
    });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('helic3Correos/actualizarPlantilla', {
      id: 1,
      data: { asunto: 'Nuevo', cuerpo: 'x' },
    });
  });

  it('alternarActivo invierte el valor actual', async () => {
    const wrapper = montar();
    wrapper
      .findComponent(PlantillaCorreoCard)
      .vm.$emit('alternarActivo', plantillasRef.value[0]);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('helic3Correos/actualizarPlantilla', {
      id: 1,
      data: { activo: false },
    });
  });

  it('previsualizar pinta el asunto y el cuerpo en un iframe', async () => {
    dispatch.mockImplementation(accion =>
      accion === 'helic3Correos/vistaPrevia'
        ? Promise.resolve({ asunto: 'Asunto real', cuerpo_html: '<p>Hola</p>' })
        : Promise.resolve()
    );
    const wrapper = montar();
    wrapper.findComponent(PlantillaCorreoCard).vm.$emit('previsualizar', 1);
    await flushPromises();

    expect(wrapper.text()).toContain('Asunto real');
    expect(wrapper.find('[data-testid="iframe-previa"]').exists()).toBe(true);
  });

  it('un fallo al previsualizar no rompe el panel', async () => {
    dispatch.mockImplementation(accion =>
      accion === 'helic3Correos/vistaPrevia'
        ? Promise.reject(new Error('x'))
        : Promise.resolve()
    );
    const wrapper = montar();
    wrapper.findComponent(PlantillaCorreoCard).vm.$emit('previsualizar', 1);
    await flushPromises();

    expect(wrapper.exists()).toBe(true);
    expect(wrapper.find('[data-testid="iframe-previa"]').exists()).toBe(false);
  });

  it('enviar prueba despacha enviarPrueba y avisa', async () => {
    const wrapper = montar();
    wrapper.findComponent(PlantillaCorreoCard).vm.$emit('prueba', 1);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('helic3Correos/enviarPrueba', 1);
    expect(alert).toHaveBeenCalledWith('TICKETS.CORREOS.PRUEBA_ENVIADA');
  });

  it('ofrece crear una plantilla solo para los procesos activos que no tienen una (D2)', () => {
    const wrapper = montar();
    // proceso 10 ya tiene plantilla, 30 esta inactivo: solo 20 deberia ofrecerse.
    expect(wrapper.find('[data-testid="btn-nueva-20"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="btn-nueva-10"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="btn-nueva-30"]').exists()).toBe(false);
  });

  it('ofrece crear la plantilla de cierre de caso cuando todavia no existe', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-testid="btn-nueva-cierre-caso"]').exists()).toBe(
      true
    );
  });

  it('crear una plantilla para un proceso despacha crearPlantilla con proceso_garantia', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="btn-nueva-20"]').trigger('click');
    await wrapper
      .find('[data-testid="input-nuevo-asunto"]')
      .setValue('Lo sentimos {{CLIENTE}}');
    await wrapper.find('[data-testid="input-nuevo-cuerpo"]').setValue('x');
    await wrapper.findComponent(Dialog).vm.$emit('confirm');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('helic3Correos/crearPlantilla', {
      disparador: 'proceso_garantia',
      proceso_garantia_id: 20,
      asunto: 'Lo sentimos {{CLIENTE}}',
      cuerpo: 'x',
    });
  });

  it('crear la plantilla de cierre de caso despacha crearPlantilla sin proceso', async () => {
    const wrapper = montar();
    await wrapper
      .find('[data-testid="btn-nueva-cierre-caso"]')
      .trigger('click');
    await wrapper.find('[data-testid="input-nuevo-asunto"]').setValue('Asunto');
    await wrapper.find('[data-testid="input-nuevo-cuerpo"]').setValue('Cuerpo');
    await wrapper.findComponent(Dialog).vm.$emit('confirm');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('helic3Correos/crearPlantilla', {
      disparador: 'cierre_caso',
      proceso_garantia_id: undefined,
      asunto: 'Asunto',
      cuerpo: 'Cuerpo',
    });
  });

  it('copiar un marcador escribe {{NOMBRE}} en el portapapeles', async () => {
    const writeText = vi.fn().mockResolvedValue();
    Object.assign(navigator, { clipboard: { writeText } });
    const wrapper = montar();
    await wrapper.find('[data-testid="copiar-CLIENTE"]').trigger('click');
    expect(writeText).toHaveBeenCalledWith('{{CLIENTE}}');
  });
});
