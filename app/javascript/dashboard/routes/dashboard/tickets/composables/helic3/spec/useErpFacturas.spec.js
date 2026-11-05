import { reactive } from 'vue';
import { useErpFacturas } from '../useErpFacturas';

const FACTURAS = [
  {
    numero: 'FV-1001',
    fecha: '2026-05-10',
    total: 1800000,
    centro_operacion: 'Armenia Centro',
    items: [
      { referencia: 'MIL-200', descripcion: 'Puerta Milano', cantidad: 2, valor: 900000 },
      { referencia: 'CER-050', descripcion: 'Cerradura Premium', cantidad: 1, valor: 900000 },
    ],
  },
  {
    numero: 'FV-1002',
    fecha: '2026-06-02',
    items: [{ referencia: 'LAM-010', descripcion: 'Lampara', cantidad: 1, valor: 450000 }],
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
    expect(erp.facturas.value).toHaveLength(2);
    expect(erp.estado.value).toBe('con_resultados');
  });

  it('recibir sin facturas deja sin_resultados (no es error)', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir([]);
    expect(erp.facturas.value).toEqual([]);
    expect(erp.estado.value).toBe('sin_resultados');
  });

  it('recibir ordena las facturas de la mas reciente a la mas vieja (m1)', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir([
      { numero: 'VIEJA', fecha: '2026-01-01', items: [] },
      { numero: 'NUEVA', fecha: '2026-09-01', items: [] },
    ]);
    expect(erp.facturas.value.map(f => f.numero)).toEqual(['NUEVA', 'VIEJA']);
  });

  it('alternar (por indice de linea) elige un producto y llena los campos sueltos', () => {
    const form = nuevoForm();
    const erp = useErpFacturas(form);
    erp.recibir(FACTURAS);

    erp.alternar(FACTURAS[0], 0);

    expect(erp.estaElegido(FACTURAS[0], 0)).toBe(true);
    expect(form.numero_orden).toBe('FV-1001');
    expect(form.producto_nombre).toBe('Puerta Milano');
    expect(form.producto_referencia).toBe('MIL-200');
  });

  it('alternar varios productos de una factura: productosElegidos los trae todos', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir(FACTURAS);

    erp.alternar(FACTURAS[0], 0);
    erp.alternar(FACTURAS[0], 1);

    expect(erp.productosElegidos()).toEqual([
      { nombre: 'Puerta Milano', referencia: 'MIL-200' },
      { nombre: 'Cerradura Premium', referencia: 'CER-050' },
    ]);
  });

  // Jhan 2a vuelta: dos lineas con la MISMA referencia no se pueden marcar juntas ni duplicar.
  it('dos lineas con la misma referencia se eligen por separado (no juntas)', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir([
      {
        numero: 'FV-DUP',
        fecha: '2026-05-10',
        items: [
          { referencia: 'REP-1', descripcion: 'Repisa (unidad A)', cantidad: 1, valor: 100 },
          { referencia: 'REP-1', descripcion: 'Repisa (unidad B)', cantidad: 1, valor: 100 },
        ],
      },
    ]);
    const dup = erp.facturas.value[0];

    erp.alternar(dup, 0);

    expect(erp.estaElegido(dup, 0)).toBe(true);
    expect(erp.estaElegido(dup, 1)).toBe(false); // la otra linea NO queda marcada
    expect(erp.productosElegidos()).toEqual([{ nombre: 'Repisa (unidad A)', referencia: 'REP-1' }]);
  });

  it('elegir un producto de otra factura cambia de factura (no mezcla)', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir(FACTURAS);

    erp.alternar(FACTURAS[0], 0);
    erp.alternar(FACTURAS[1], 0);

    expect(erp.facturaElegida.value).toBe('FV-1002');
    expect(erp.productosElegidos()).toEqual([{ nombre: 'Lampara', referencia: 'LAM-010' }]);
  });

  it('alternar dos veces la misma linea la quita (y deja la factura sin elegir)', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir(FACTURAS);

    erp.alternar(FACTURAS[0], 0);
    erp.alternar(FACTURAS[0], 0);

    expect(erp.productosElegidos()).toEqual([]);
    expect(erp.facturaElegida.value).toBeNull();
  });

  it('limpiar vacia las facturas y la seleccion', () => {
    const erp = useErpFacturas(nuevoForm());
    erp.recibir(FACTURAS);
    erp.alternar(FACTURAS[0], 0);

    erp.limpiar();

    expect(erp.facturas.value).toEqual([]);
    expect(erp.facturaElegida.value).toBeNull();
    expect(erp.estado.value).toBe('idle');
  });
});
