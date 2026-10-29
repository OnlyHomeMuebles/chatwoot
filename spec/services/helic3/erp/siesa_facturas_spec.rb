# frozen_string_literal: true

require 'rails_helper'

# ERP-05: el parser de la respuesta de API_v2_Ventas_Facturas_DesdePedido. Pura (sin red):
# toma el JSON que devuelve Siesa HUB y arma las facturas del contrato, agrupando las
# lineas por documento (f350_rowid). Diseno segun el doc de Jhan (27-oct): la llave es
# prefijo + consecutivo; el centro de operacion va aparte.
RSpec.describe Helic3::Erp::SiesaFacturas do
  # Respuesta grabada (recortada a los campos que se usan): 2 facturas, la 1ra con 2 lineas.
  let(:respuesta) do
    {
      'codigo' => 0,
      'mensaje' => 'Transaccion Exitosa',
      'detalle' => {
        'Table' => [
          linea(rowid: 339, co: '012', consec: 974, prefijo: '    ', fecha: '2023-04-03T00:00:00',
                nit: '26478046', neto: 1_497_100, cxc: 1_497_100,
                ref: '2000004000165', desc: 'JUEGO COMEDOR PUFF ROYAL', cant: 1, vlr: 859_000),
          linea(rowid: 339, co: '012', consec: 974, prefijo: '    ', fecha: '2023-04-03T00:00:00',
                nit: '26478046', neto: 1_497_100, cxc: 1_497_100,
                ref: '2050003000065', desc: 'SOFACAMA DELTA OTAWA', cant: 1, vlr: 638_100),
          linea(rowid: 348, co: '014', consec: 563, prefijo: '    ', fecha: '2023-04-03T00:00:00',
                nit: '38600294', neto: 1_285_000, cxc: 1_285_000,
                ref: '2000004000002', desc: 'MESA COMEDOR CALYPSO', cant: 1, vlr: 449_000)
        ]
      }
    }
  end

  def linea(rowid:, co:, consec:, prefijo:, fecha:, nit:, neto:, cxc:, ref:, desc:, cant:, vlr:)
    {
      'f350_rowid' => rowid, 'f350_id_co' => co, 'f350_consec_docto' => consec,
      'f350_prefijo' => prefijo, 'f350_id_tipo_docto' => 'FVE', 'f350_fecha' => fecha,
      'f200_nit_fact' => nit, 'f461_vlr_neto' => neto, 'f461_vlr_cxc' => cxc,
      'f120_referencia' => ref, 'f120_descripcion' => desc, 'f470_cant_1' => cant, 'f470_vlr_neto' => vlr
    }
  end

  it 'agrupa las lineas por documento: 3 lineas -> 2 facturas' do
    facturas = described_class.parsear(respuesta)
    expect(facturas.size).to eq(2)
    expect(facturas).to all(be_a(Helic3::Erp::Invoice))
  end

  it 'arma la factura con sus productos y el centro de operacion' do
    factura = described_class.parsear(respuesta).find { |f| f.items.size == 2 }

    expect(factura.centro_operacion).to eq('012')
    expect(factura.fecha).to eq('2023-04-03') # recorta la hora
    expect(factura.total).to eq(1_497_100)
    expect(factura.items.map(&:referencia)).to contain_exactly('2000004000165', '2050003000065')
    item = factura.items.first
    expect(item).to have_attributes(descripcion: 'JUEGO COMEDOR PUFF ROYAL', cantidad: 1, valor: 859_000)
  end

  it 'arma el numero con prefijo + consecutivo' do
    numeros = described_class.parsear(respuesta).map(&:numero)
    expect(numeros).to contain_exactly('974', '563') # prefijo en blanco -> solo consecutivo
  end

  it 'codigo 1 (sin registros) devuelve lista vacia, no error' do
    sin_registros = { 'codigo' => 1, 'mensaje' => 'Error', 'detalle' => 'No se encontraron registros' }
    expect(described_class.parsear(sin_registros)).to eq([])
  end

  it 'no revienta si detalle no es un Hash (codigo como string, o payload de error) -> []' do
    # Siesa a veces manda codigo como string ("1") y detalle como texto; el parseo no puede
    # depender de que codigo sea el entero 1: debe mirar si hay una tabla de filas.
    ['1', 2, '2'].each do |codigo|
      cuerpo = { 'codigo' => codigo, 'detalle' => 'No se encontraron registros' }
      expect(described_class.parsear(cuerpo)).to eq([])
    end
  end

  it 'nombre_cliente saca el razon_social del facturado (primera fila, sin espacios)' do
    cuerpo = { 'codigo' => 0, 'detalle' => { 'Table' => [
      { 'f350_rowid' => 1, 'f200_razon_social_fact' => '  LLANOS HERRERA MAGDA JOHANA  ' }
    ] } }
    expect(described_class.nombre_cliente(cuerpo)).to eq('LLANOS HERRERA MAGDA JOHANA')
  end

  it 'nombre_cliente devuelve nil si no hay compras' do
    expect(described_class.nombre_cliente({ 'codigo' => 1, 'detalle' => 'No se encontraron registros' })).to be_nil
  end
end
