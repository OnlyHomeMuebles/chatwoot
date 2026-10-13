# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::PlantillaFormato do
  let(:account) { create(:account) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }

  def nueva(estado:, version:)
    described_class.create!(account: account, formato: formato, version: version, estado: estado, marcadores: [])
  end

  it 'rechaza un estado invalido' do
    plantilla = described_class.new(account: account, formato: formato, version: 1, estado: 'otro')
    expect(plantilla).not_to be_valid
  end

  it 'no permite dos versiones iguales por formato (indice unico)' do
    nueva(estado: 'borrador', version: 1)
    expect { nueva(estado: 'borrador', version: 1) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'no permite dos activas del mismo formato (indice parcial) [CA5]' do
    nueva(estado: 'activa', version: 1)
    expect { nueva(estado: 'activa', version: 2) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'no borra una activa o retirada; si borra un borrador [CA6]' do
    activa = nueva(estado: 'activa', version: 1)
    expect(activa.destroy).to be_falsey
    borrador = nueva(estado: 'borrador', version: 2)
    expect(borrador.destroy).to be_truthy
  end

  it 'scope activa devuelve solo las activas' do
    nueva(estado: 'activa', version: 1)
    nueva(estado: 'borrador', version: 2)
    expect(described_class.activa.count).to eq(1)
  end
end
