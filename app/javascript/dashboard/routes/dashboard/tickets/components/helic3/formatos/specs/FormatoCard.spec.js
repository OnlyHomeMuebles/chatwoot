import { shallowMount } from '@vue/test-utils';
import FormatoCard from '../FormatoCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: clave => clave }) }));

const formatoConActiva = {
  id: 1,
  codigo: 'visita_tecnica',
  nombre: 'Visita técnica',
  activa_id: 10,
  versiones: [
    { id: 10, version: 3, estado: 'activa', marcadores: ['CLIENTE'] },
  ],
};
const formatoSinActiva = {
  id: 2,
  codigo: 'recoleccion',
  nombre: 'Recolección',
  activa_id: null,
  versiones: [],
};

const montar = props =>
  shallowMount(FormatoCard, { props: { esAdmin: true, ...props } });

describe('FormatoCard', () => {
  it('muestra el nombre del formato', () => {
    expect(montar({ formato: formatoConActiva }).text()).toContain(
      'Visita técnica'
    );
  });

  it('un formato sin activa avisa que no tiene plantilla', () => {
    const wrapper = montar({ formato: formatoSinActiva });
    expect(wrapper.find('[data-testid="sin-plantilla"]').exists()).toBe(true);
  });

  it('un agente (no admin) no ve el boton de subir', () => {
    const wrapper = montar({ formato: formatoConActiva, esAdmin: false });
    expect(wrapper.find('[data-testid="btn-subir"]').exists()).toBe(false);
  });

  it('un admin si ve el boton de subir', () => {
    const wrapper = montar({ formato: formatoConActiva });
    expect(wrapper.find('[data-testid="btn-subir"]').exists()).toBe(true);
  });

  it('muestra los marcadores desconocidos del 422', () => {
    const wrapper = montar({
      formato: formatoConActiva,
      desconocidos: ['CLEINTE'],
    });
    expect(wrapper.find('[data-testid="desconocidos"]').text()).toContain(
      'CLEINTE'
    );
  });

  it('emite subir cuando el admin elige un archivo', async () => {
    const wrapper = montar({ formato: formatoConActiva });
    const input = wrapper.find('[data-testid="input-archivo"]');
    Object.defineProperty(input.element, 'files', {
      value: [new File(['x'], 'p.docx')],
      configurable: true,
    });
    await input.trigger('change');
    expect(wrapper.emitted('subir')).toBeTruthy();
    expect(wrapper.emitted('subir')[0][0].formato).toStrictEqual(
      formatoConActiva
    );
    expect(wrapper.emitted('subir')[0][0].archivo.name).toBe('p.docx');
  });

  it('al confirmar, emite activar y CIERRA el dialogo', () => {
    const close = vi.fn();
    const formatoConBorrador = {
      id: 3,
      codigo: 'x',
      nombre: 'X',
      activa_id: null,
      versiones: [{ id: 20, version: 1, estado: 'borrador', marcadores: [] }],
    };
    const wrapper = shallowMount(FormatoCard, {
      props: { esAdmin: true, formato: formatoConBorrador },
      global: {
        stubs: {
          Dialog: {
            name: 'Dialog',
            template: '<div />',
            methods: { open: vi.fn(), close },
          },
        },
      },
    });
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    expect(wrapper.emitted('activar')[0]).toEqual([20]);
    expect(close).toHaveBeenCalled();
  });
});
