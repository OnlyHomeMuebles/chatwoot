# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Erp::SiesaCentros do
  let(:respuesta) do
    JSON.parse(File.read(Rails.root.join('spec/fixtures/helic3/centros_operacion_siesa.json')))
  end

  it 'concatena las filas partidas de detalle.Table y parsea los centros' do
    centros = described_class.parsear(respuesta)

    expect(centros.size).to eq(3)
  end

  it 'incluye los centros inactivos (no los filtra)' do
    centros = described_class.parsear(respuesta)

    expect(centros.count { |c| !c[:activo] }).to eq(1)
    expect(centros.find { |c| c[:id] == '012' }[:activo]).to be(false)
  end

  it 'indexa por compañía + id: el mismo id da nombre distinto según la compañía' do
    centros = described_class.parsear(respuesta)

    expect(described_class.nombre(centros, compania: 1, id: '001')).to eq('OM CALI SUR')
    expect(described_class.nombre(centros, compania: 2, id: '001')).to eq('INDIGO MALL')
  end

  it 'nombre devuelve nil si no hay centro para esa compañía + id' do
    centros = described_class.parsear(respuesta)

    expect(described_class.nombre(centros, compania: 9, id: '999')).to be_nil
  end

  it 'devuelve [] cuando la respuesta no trae tabla (sin registros, detalle como texto)' do
    expect(described_class.parsear({ 'codigo' => 1, 'detalle' => 'Sin registros' })).to eq([])
  end

  describe '.con_nombre (pega el nombre del C.O. a cada factura)' do
    def factura(compania:, centro:)
      Helic3::Erp::Invoice.new(numero: 'FV-1', fecha: '2023-04-03', total: 100, saldo: 0,
                               estado: nil, centro_operacion: centro, centro_operacion_compania: compania)
    end

    it 'resuelve por compañía + id: el mismo id da nombre distinto según la compañía (CA8)' do
      facturas = [factura(compania: 1, centro: '001'), factura(compania: 2, centro: '001')]

      resueltas = described_class.con_nombre(facturas, respuesta)

      expect(resueltas.map(&:centro_operacion_nombre)).to eq(['OM CALI SUR', 'INDIGO MALL'])
    end

    it 'resuelve también los centros inactivos (CA10)' do
      resueltas = described_class.con_nombre([factura(compania: 1, centro: '012')], respuesta)

      expect(resueltas.first.centro_operacion_nombre).to eq('OM NEIVA')
    end

    it 'si el id no está en la lista, deja el nombre en nil y conserva el id (CA2)' do
      resueltas = described_class.con_nombre([factura(compania: 9, centro: '999')], respuesta)

      expect(resueltas.first.centro_operacion_nombre).to be_nil
      expect(resueltas.first.centro_operacion).to eq('999')
    end

    it 'sin tabla de centros, deja las facturas con nombre nil (no revienta)' do
      resueltas = described_class.con_nombre([factura(compania: 1, centro: '001')],
                                             { 'codigo' => 1, 'detalle' => 'Sin registros' })

      expect(resueltas.first.centro_operacion_nombre).to be_nil
    end
  end
end
