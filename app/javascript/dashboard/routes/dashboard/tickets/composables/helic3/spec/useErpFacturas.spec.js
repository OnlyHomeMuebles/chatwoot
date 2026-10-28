import { reactive } from 'vue';
import { useErpFacturas } from '../useErpFacturas';

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
  it('recibir con facturas marca con_resultados', () => {
    const erp = useErpFacturas(nuevoForm());

    erp.recibir(FACTURAS);

    expect(erp.facturas.value).toHaveLength(1);
    expect(erp.facturas.value[0].numero).toBe('FV-1001');
    expect(erp.estado.value).toBe('con_resultados');
  });

  it('recibir sin facturas deja sin_resultados (no es error)', () => {
    const erp = useErpFacturas(nuevoForm());

    erp.recibir([]);

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

  it('limpiar vacia las facturas y resetea el estado', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir(FACTURAS);

    erp.limpiar();

    expect(erp.facturas.value).toEqual([]);
    expect(erp.estado.value).toBe('idle');
  });
});
