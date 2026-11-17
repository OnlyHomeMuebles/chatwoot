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
end
