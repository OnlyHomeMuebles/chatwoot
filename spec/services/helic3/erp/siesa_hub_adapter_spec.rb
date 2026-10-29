# frozen_string_literal: true

require 'rails_helper'

# ERP-05: el adaptador real. Se le inyecta un cliente HTTP falso, asi se prueba el armado del
# filtro, el parseo y las DOS consultas (clientes + compras) SIN pegarle a Siesa.
RSpec.describe Helic3::Erp::SiesaHubAdapter do
  let(:cliente) { instance_double(Helic3::Erp::SiesaHubCliente) }

  subject(:adapter) do
    described_class.new(cliente: cliente, consultas_compras: ['API_v2_Ventas_Facturas_DesdePedido'],
                        consulta_clientes: 'enterprise_mm_terceros_clie_v1')
  end

  def compras(consec)
    { 'codigo' => 0, 'detalle' => { 'Table' => [
      { 'f350_rowid' => consec, 'f350_id_co' => '012', 'f350_consec_docto' => consec, 'f350_prefijo' => '    ',
        'f350_fecha' => '2023-04-03T00:00:00', 'f461_vlr_neto' => 100, 'f461_vlr_cxc' => 100,
        'f120_referencia' => 'R1', 'f120_descripcion' => 'P1', 'f470_cant_1' => 1, 'f470_vlr_neto' => 100 }
    ] } }
  end

  def tercero(nombres:, ape1:, ape2:, tel: '3219222701', email: 'JOHNALLANOS@HOTMAIL.COM', dir: 'CR 1 A 1 62 115')
    { 'codigo' => 0, 'detalle' => { 'Table' => [
      { 'id' => '26478046', 'nombres' => nombres, 'apellido1' => ape1, 'apellido2' => ape2,
        'razonSocial' => "#{ape1} #{ape2} #{nombres}", 'telefono' => tel, 'email' => email,
        'direccion1' => dir, 'idCiudad' => '001', 'idDepto' => '63' }
    ] } }
  end

  describe '#invoices' do
    it 'arma el filtro por cedula+fecha (desde, que pasa el cache) y parsea las facturas' do
      expect(cliente).to receive(:consultar)
        .with(descripcion: 'API_v2_Ventas_Facturas_DesdePedido',
              parametros: "f200_nit_fact=''26478046'' and f350_fecha >= ''2023-01-01''")
        .and_return(compras(974))

      expect(adapter.invoices(cedula: '26478046', desde: '2023-01-01').map(&:numero)).to eq(['974'])
    end

    it 'concatena las facturas de varias fuentes' do
      multi = described_class.new(cliente: cliente, consultas_compras: %w[A B], consulta_clientes: 'C')
      allow(cliente).to receive(:consultar).and_return(compras(1), compras(2))

      expect(multi.invoices(cedula: '1', desde: '2023-01-01').map(&:numero)).to contain_exactly('1', '2')
    end

    it 'sanea la cedula a solo digitos antes del filtro (defensa ante inyeccion)' do
      expect(cliente).to receive(:consultar)
        .with(descripcion: anything, parametros: "f200_nit_fact=''123'' and f350_fecha >= ''2023-01-01''")
        .and_return(compras(974))

      adapter.invoices(cedula: "123'' or ''a''=''a", desde: '2023-01-01')
    end
  end

  describe '#find_customer (consulta de clientes / terceros)' do
    it 'consulta el maestro de clientes por cedula (filtro id) y arma nombre + contacto' do
      expect(cliente).to receive(:consultar)
        .with(descripcion: 'enterprise_mm_terceros_clie_v1', parametros: "id=''26478046''")
        .and_return(tercero(nombres: 'MAGDA JOHANA', ape1: 'LLANOS', ape2: 'HERRERA'))

      cli = adapter.find_customer(cedula: '26478046')
      expect(cli.nombre).to eq('MAGDA JOHANA LLANOS HERRERA')
      expect(cli.cedula).to eq('26478046')
      expect(cli.telefono).to eq('3219222701')
      expect(cli.email).to eq('JOHNALLANOS@HOTMAIL.COM')
      expect(cli.direccion).to eq('CR 1 A 1 62 115')
      expect(cli.ciudad).to be_nil # viene como codigo; se traduce en un follow-up
    end

    it 'trae el nombre aunque la cedula NO tenga compras (es el maestro, no las ventas)' do
      allow(cliente).to receive(:consultar).and_return(tercero(nombres: 'SAMUEL', ape1: 'MARIN', ape2: 'ARANGO'))

      expect(adapter.find_customer(cedula: '1092852257').nombre).to eq('SAMUEL MARIN ARANGO')
    end

    it 'devuelve nil si la cedula no esta en el maestro' do
      allow(cliente).to receive(:consultar).and_return({ 'codigo' => 1, 'detalle' => 'No se encontraron registros' })

      expect(adapter.find_customer(cedula: '999')).to be_nil
    end
  end
end
