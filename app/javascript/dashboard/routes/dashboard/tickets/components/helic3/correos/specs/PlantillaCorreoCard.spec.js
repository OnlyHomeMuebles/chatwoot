import { shallowMount } from '@vue/test-utils';
import PlantillaCorreoCard from '../PlantillaCorreoCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: clave => clave }) }));

const plantilla = {
  id: 1,
  disparador: 'proceso_garantia',
  proceso_garantia_id: 5,
  proceso_nombre: 'Visita técnica',
  asunto: 'Hola {{CLIENTE}}',
  cuerpo: 'Cuerpo original',
  activo: true,
};

const montar = (props = {}) =>
  shallowMount(PlantillaCorreoCard, {
    props: { plantilla, esAdmin: true, ...props },
  });

describe('PlantillaCorreoCard', () => {
  it('muestra el nombre del proceso como titulo', () => {
    const wrapper = montar();
    expect(wrapper.text()).toContain('Visita técnica');
  });

  it('muestra "Cierre de caso" cuando el disparador no cuelga de un proceso', () => {
    const wrapper = montar({
      plantilla: {
        ...plantilla,
        disparador: 'cierre_caso',
        proceso_garantia_id: null,
        proceso_nombre: null,
      },
    });
    expect(wrapper.text()).toContain('TICKETS.CORREOS.CIERRE_CASO');
  });

  it('guardar no emite nada mientras no cambie asunto o cuerpo', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="btn-guardar"]').trigger('click');
    expect(wrapper.emitted('guardar')).toBeUndefined();

    await wrapper.find('[data-testid="input-asunto"]').setValue('Nuevo asunto');
    await wrapper.find('[data-testid="btn-guardar"]').trigger('click');
    expect(wrapper.emitted('guardar')).toHaveLength(1);
  });

  it('guardar emite solo asunto/cuerpo del id correspondiente', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="input-cuerpo"]').setValue('Cuerpo nuevo');
    await wrapper.find('[data-testid="btn-guardar"]').trigger('click');

    expect(wrapper.emitted('guardar')[0]).toEqual([
      { id: 1, data: { asunto: 'Hola {{CLIENTE}}', cuerpo: 'Cuerpo nuevo' } },
    ]);
  });

  it('previsualizar emite el id sin pedir permiso de admin', async () => {
    const wrapper = montar({ esAdmin: false });
    await wrapper.find('[data-testid="btn-previa"]').trigger('click');
    expect(wrapper.emitted('previsualizar')).toEqual([[1]]);
  });

  it('un agente (no admin) no ve los controles de edicion', () => {
    const wrapper = montar({ esAdmin: false });
    expect(wrapper.find('[data-testid="btn-guardar"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="btn-prueba"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="btn-alternar-activo"]').exists()).toBe(
      false
    );
  });

  it('alternarActivo emite la plantilla completa', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="btn-alternar-activo"]').trigger('click');
    expect(wrapper.emitted('alternarActivo')).toEqual([[plantilla]]);
  });
});
