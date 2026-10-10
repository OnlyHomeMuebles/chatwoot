# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::VistaPrevia do
  let(:account) { create(:account) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }
  let(:plantilla) do
    nueva = formato.plantillas.create!(account: account, version: 1, estado: 'activa', marcadores: %w[CLIENTE])
    nueva.fodt.attach(io: StringIO.new('<office/>'), filename: 'p.fodt', content_type: 'text/xml')
    nueva
  end

  before { allow(Helic3::Formatos::LlenarPlantilla).to receive(:call).and_return('<office/>') }

  it 'sin item usa DATOS_DE_EJEMPLO y devuelve un PDF [CA7]' do
    allow(Helic3::Formatos::Conversor).to receive(:a_pdf).and_return('%PDF-1.7 ok')

    resultado = described_class.call(plantilla: plantilla)

    expect(resultado[:extension]).to eq('pdf')
    expect(resultado[:bytes]).to start_with('%PDF')
  end

  it 'con formato :docx devuelve bytes de Word' do
    allow(Helic3::Formatos::Conversor).to receive(:a_docx).and_return("PK\x03\x04 ok")

    resultado = described_class.call(plantilla: plantilla, formato: :docx)

    expect(resultado[:extension]).to eq('docx')
    expect(resultado[:bytes]).to start_with('PK')
  end

  it 'rechaza un formato no soportado' do
    expect { described_class.call(plantilla: plantilla, formato: :xlsx) }.to raise_error(ArgumentError)
  end
end
