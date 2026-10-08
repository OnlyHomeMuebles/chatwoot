# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Catalogo::Formato do
  let(:account) { create(:account) }

  it 'usa la tabla helic3_catalogo_formatos' do
    expect(described_class.table_name).to eq('helic3_catalogo_formatos')
  end

  it 'valida nombre y codigo por cuenta (via Comun)' do
    described_class.create!(account: account, nombre: 'A', codigo: 'x', posicion: 0)
    dup = described_class.new(account: account, nombre: 'B', codigo: 'x', posicion: 1)
    expect(dup).not_to be_valid
  end

  it 'la siembra deja los 4 formatos por cuenta, idempotente' do
    Helic3::Catalogo::SeederService.new(account).sembrar!
    Helic3::Catalogo::SeederService.new(account).sembrar!
    expect(described_class.where(account: account).count).to eq(4)
    expect(described_class.where(account: account).pluck(:codigo)).to contain_exactly(
      'cumplimiento_mercancia_reparada', 'visita_tecnica',
      'recoleccion_productos', 'cumplimiento_cambio_devolucion'
    )
  end
end
