# frozen_string_literal: true

require 'rails_helper'

# ERP-15 (B3): escribe la compra marcando la procedencia, cruzando factura+productos contra
# el cache del ERP. El simulado hace de ERP: Ana (1032456789) tiene FV-1001 con dos productos
# (MIL-200 'Puerta Milano' y CER-050 'Cerradura Premium').
RSpec.describe Helic3::Casos::RegistrarCompraErp do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  around { |ejemplo| with_modified_env(HELIC3_ERP_MODO: 'simulado') { ejemplo.run } }

  it 'cruza la factura y los productos elegidos: fuente erp y lista de productos' do
    described_class.new(ticket: ticket, cedula: '1032456789',
                        datos: { factura_numero: 'FV-1001', factura_fecha: '2026-05-10',
                                 productos: [{ referencia: 'MIL-200' }, { referencia: 'CER-050' }] }).call

    ficha = ticket.reload.datos
    expect(ficha.factura_numero).to eq('FV-1001')
    expect(ficha.fuentes['factura_numero']).to eq('erp')
    expect(ficha.productos.map { |p| p['referencia'] }).to eq(%w[MIL-200 CER-050])
    expect(ficha.productos.map { |p| p['fuente'] }).to all(eq('erp'))
    # el primero tambien a los campos sueltos, con su fuente
    expect(ficha.producto_nombre).to eq('Puerta Milano')
    expect(ficha.fuentes['producto_nombre']).to eq('erp')
  end

  it 'un producto que el agente agrego a mano y no cruza queda humano' do
    described_class.new(ticket: ticket, cedula: '1032456789',
                        datos: { factura_numero: 'FV-1001',
                                 productos: [{ referencia: 'MIL-200' },
                                             { nombre: 'Lampara a mano', referencia: 'X-999' }] }).call

    ficha = ticket.reload.datos
    erp = ficha.productos.find { |p| p['referencia'] == 'MIL-200' }
    humano = ficha.productos.find { |p| p['referencia'] == 'X-999' }
    expect(erp['fuente']).to eq('erp')
    expect(humano).to include('fuente' => 'humano', 'nombre' => 'Lampara a mano')
  end

  it 'si la factura no esta en el cache, la fecha y los productos quedan humano' do
    described_class.new(ticket: ticket, cedula: '1032456789',
                        datos: { factura_numero: 'NO-EXISTE', factura_fecha: '2026-01-01',
                                 productos: [{ nombre: 'Algo', referencia: 'Z-1' }] }).call

    ficha = ticket.reload.datos
    expect(ficha.fuentes['factura_fecha']).to eq('humano')
    expect(ficha.productos.first['fuente']).to eq('humano')
  end

  it 'si el ERP falla, no cruza nada: todo humano, sin reventar la radicacion' do
    allow(Helic3::Erp::Cache).to receive(:consultar).and_raise(StandardError)

    expect do
      described_class.new(ticket: ticket, cedula: '1032456789',
                          datos: { factura_numero: 'FV-1001',
                                   productos: [{ nombre: 'Puerta', referencia: 'MIL-200' }] }).call
    end.not_to raise_error

    expect(ticket.reload.datos.productos.first['fuente']).to eq('humano')
  end
end
