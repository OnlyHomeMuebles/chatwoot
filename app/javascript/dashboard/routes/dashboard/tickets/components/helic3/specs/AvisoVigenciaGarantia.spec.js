import { mount } from '@vue/test-utils';
import AvisoVigenciaGarantia from '../AvisoVigenciaGarantia.vue';

// t: key => key para asertar sobre las claves i18n (no sobre el texto traducido).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const montar = vigencia =>
  mount(AvisoVigenciaGarantia, { props: { vigencia } });

const aviso = wrapper => wrapper.find('[data-testid="aviso-vigencia"]');

describe('AvisoVigenciaGarantia.vue (GAR-09)', () => {
  it('no pinta nada cuando vigencia es null', () => {
    expect(aviso(montar(null)).exists()).toBe(false);
  });

  it('estado dentro: aviso verde (teal) con su título', () => {
    const wrapper = montar({
      estado: 'dentro',
      fecha_radicacion: '2026-11-25',
      amparo_hasta: '2027-02-10',
      amparo_meses: 12,
      antiguedad_meses: 9,
    });

    expect(aviso(wrapper).exists()).toBe(true);
    expect(aviso(wrapper).classes()).toContain('bg-n-teal-3');
    expect(wrapper.text()).toContain('TICKETS.DATA.VIGENCIA.DENTRO_TITLE');
  });

  it('estado fuera: aviso rojo (ruby) con su título', () => {
    const wrapper = montar({
      estado: 'fuera',
      fecha_radicacion: '2026-11-25',
      amparo_hasta: '2025-09-13',
      amparo_meses: 12,
      antiguedad_meses: 26,
    });

    expect(aviso(wrapper).classes()).toContain('bg-n-ruby-3');
    expect(wrapper.text()).toContain('TICKETS.DATA.VIGENCIA.FUERA_TITLE');
  });

  it('estado sin_fecha_compra: aviso ámbar con su título', () => {
    const wrapper = montar({ estado: 'sin_fecha_compra', amparo_meses: 12 });

    expect(aviso(wrapper).classes()).toContain('bg-n-amber-3');
    expect(wrapper.text()).toContain('TICKETS.DATA.VIGENCIA.SIN_FECHA_TITLE');
  });
});
