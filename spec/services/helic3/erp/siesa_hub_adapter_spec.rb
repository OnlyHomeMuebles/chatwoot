# frozen_string_literal: true

require 'rails_helper'

# ERP-05: el adaptador real. Se le inyecta un cliente HTTP falso, asi se prueba el armado
# del filtro, el parseo y la concatenacion de fuentes SIN pegarle a Siesa.
RSpec.describe Helic3::Erp::SiesaHubAdapter do
  let(:cliente) { instance_double(Helic3::Erp::SiesaHubCliente) }

  subject(:adapter) do
    described_class.new(cliente: cliente, consultas_compras: ['API_v2_Ventas_Facturas_DesdePedido'],
                        desde: '2023-01-01')
  end

  def respuesta(consec)
    { 'codigo' => 0, 'detalle' => { 'Table' => [
      { 'f350_rowid' => consec, 'f350_id_co' => '012', 'f350_consec_docto' => consec, 'f350_prefijo' => '    ',
        'f350_id_tipo_docto' => 'FVE', 'f350_fecha' => '2023-04-03T00:00:00', 'f200_nit_fact' => '26478046',
        'f200_razon_social_fact' => 'MAGDA LLANOS', 'f461_vlr_neto' => 100, 'f461_vlr_cxc' => 100,
        'f120_referencia' => 'R1', 'f120_descripcion' => 'P1', 'f470_cant_1' => 1, 'f470_vlr_neto' => 100 }
    ] } }
  end

  it 'invoices: arma el filtro por cedula+fecha y parsea las facturas de la fuente' do
    expect(cliente).to receive(:consultar)
      .with(descripcion: 'API_v2_Ventas_Facturas_DesdePedido',
            parametros: "f200_nit_fact=''26478046'' and f350_fecha >= ''2023-01-01''")
      .and_return(respuesta(974))

    expect(adapter.invoices(cedula: '26478046').map(&:numero)).to eq(['974'])
  end

  it 'invoices: concatena las facturas de varias fuentes' do
    multi = described_class.new(cliente: cliente, consultas_compras: %w[A B], desde: '2023-01-01')
    allow(cliente).to receive(:consultar).and_return(respuesta(1), respuesta(2))

    expect(multi.invoices(cedula: '1').map(&:numero)).to contain_exactly('1', '2')
  end

  it 'find_customer arma el cliente con el nombre (razon_social) de la respuesta de compras' do
    allow(cliente).to receive(:consultar).and_return(respuesta(974))
    cli = adapter.find_customer(cedula: '26478046')

    expect(cli.nombre).to eq('MAGDA LLANOS')
    expect(cli.cedula).to eq('26478046')
    expect(cli.ciudad).to be_nil # ciudad/contacto llegan con la consulta de clientes (ERP-12)
  end

  it 'find_customer devuelve nil si el cliente no tiene compras (sin nombre que mostrar)' do
    allow(cliente).to receive(:consultar).and_return({ 'codigo' => 1, 'detalle' => 'No se encontraron registros' })

    expect(adapter.find_customer(cedula: '26478046')).to be_nil
  end

  it 'invoices: SIESA_HUB_DESDE (ENV) corre la ventana para probar data historica de QA' do
    with_modified_env SIESA_HUB_DESDE: '2022-01-01' do
      sin_desde = described_class.new(cliente: cliente, consultas_compras: ['A']) # sin desde: -> usa ENV
      expect(cliente).to receive(:consultar)
        .with(descripcion: 'A', parametros: "f200_nit_fact=''26478046'' and f350_fecha >= ''2022-01-01''")
        .and_return(respuesta(974))

      sin_desde.invoices(cedula: '26478046')
    end
  end

  it 'invoices: sanea la cedula a solo digitos antes de armar el filtro (defensa ante inyeccion)' do
    # La cedula se interpola en el SQL de `parametros`. Aunque hoy siempre llega normalizada,
    # el adaptador es publico: si alguien pasa comillas, no deben filtrarse al filtro.
    expect(cliente).to receive(:consultar)
      .with(descripcion: anything,
            parametros: "f200_nit_fact=''123'' and f350_fecha >= ''2023-01-01''")
      .and_return(respuesta(974))

    adapter.invoices(cedula: "123'' or ''a''=''a")
  end
end
