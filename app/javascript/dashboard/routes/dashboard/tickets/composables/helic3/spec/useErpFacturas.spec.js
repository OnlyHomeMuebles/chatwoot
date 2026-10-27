import { reactive } from 'vue';
import { useErpFacturas } from '../useErpFacturas';
import TicketsAPI from 'dashboard/api/tickets';

vi.mock('dashboard/api/tickets', () => ({
  default: { consultarErpFacturas: vi.fn() },
}));

const FACTURAS = [
  {
    numero: 'FV-1001',
    fecha: '2026-05-10',
    total: 1800000,
    centro_operacion: 'Armenia Centro',
    items: [{ referencia: 'MIL-200', descripcion: 'Puerta Milano', cantidad: 2, valor: 900000 }],
  },
];

const nuevoForm = () =>
  reactive({
    numero_orden: '',
    factura_fecha: '',
    producto_nombre: '',
    producto_referencia: '',
  });

describe('useErpFacturas (ERP-15)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('consultar trae las facturas y marca con_resultados', async () => {
    TicketsAPI.consultarErpFacturas.mockResolvedValue({ data: { facturas: FACTURAS } });
    const erp = useErpFacturas(nuevoForm());

    await erp.consultar('26478046');

    expect(erp.facturas.value).toHaveLength(1);
    expect(erp.facturas.value[0].numero).toBe('FV-1001');
    expect(erp.estado.value).toBe('con_resultados');
  });

  it('sin facturas deja estado sin_resultados (no es error)', async () => {
    TicketsAPI.consultarErpFacturas.mockResolvedValue({ data: { facturas: [] } });
    const erp = useErpFacturas(nuevoForm());

    await erp.consultar('99999999');

    expect(erp.facturas.value).toEqual([]);
    expect(erp.estado.value).toBe('sin_resultados');
  });

  it('elegir llena los 4 campos de compra del form', () => {
    const form = nuevoForm();
    const erp = useErpFacturas(form);

    erp.elegir(FACTURAS[0], FACTURAS[0].items[0]);

    expect(form.numero_orden).toBe('FV-1001');
    expect(form.factura_fecha).toBe('2026-05-10');
    expect(form.producto_nombre).toBe('Puerta Milano');
    expect(form.producto_referencia).toBe('MIL-200');
  });

  it('limpiar vacia las facturas y resetea el estado', async () => {
    TicketsAPI.consultarErpFacturas.mockResolvedValue({ data: { facturas: FACTURAS } });
    const erp = useErpFacturas(nuevoForm());
    await erp.consultar('26478046');

    erp.limpiar();

    expect(erp.facturas.value).toEqual([]);
    expect(erp.estado.value).toBe('idle');
  });

  it('con el ERP caido (503) deja no_disponible y sin facturas', async () => {
    TicketsAPI.consultarErpFacturas.mockRejectedValue({ response: { status: 503 } });
    const erp = useErpFacturas(nuevoForm());

    await erp.consultar('26478046');

    expect(erp.estado.value).toBe('no_disponible');
    expect(erp.facturas.value).toEqual([]);
  });
});
