# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::SubirPlantilla do
  let(:account) { create(:account) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }

  def archivo(nombre, contenido)
    Rack::Test::UploadedFile.new(StringIO.new(contenido), nil, original_filename: nombre)
  end

  def docx(contenido = "PK\x03\x04docx-bytes")
    archivo('plantilla.docx', contenido)
  end

  it 'sube un .docx con marcadores conocidos: ok, borrador, version 1 [CA1]' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return(%w[CLIENTE RADICADO])

    resultado = described_class.call(formato: formato, archivo: docx, user: nil)

    expect(resultado.ok?).to be(true)
    expect(resultado.plantilla.estado).to eq('borrador')
    expect(resultado.plantilla.version).to eq(1)
    expect(resultado.plantilla.marcadores).to eq(%w[CLIENTE RADICADO])
  end

  it 'rechaza un marcador desconocido, sugiere el cercano y no guarda nada [CA2]' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return(%w[CLEINTE])

    resultado = described_class.call(formato: formato, archivo: docx, user: nil)

    expect(resultado.ok?).to be(false)
    expect(resultado.errores.first).to include('{{CLEINTE}}').and include('{{CLIENTE}}')
    expect(formato.plantillas.count).to eq(0)
  end

  it 'rechaza un .xlsx y un PDF renombrado a .docx [CA8]' do
    expect(described_class.call(formato: formato, archivo: archivo('x.xlsx', 'cualquiera'), user: nil).ok?).to be(false)
    expect(described_class.call(formato: formato, archivo: archivo('x.docx', '%PDF-1.7'), user: nil).ok?).to be(false)
  end

  it 'si el Conversor falla devuelve "no se pudo leer el archivo"' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_raise(Helic3::Formatos::Conversor::Error)

    resultado = described_class.call(formato: formato, archivo: docx, user: nil)

    expect(resultado.ok?).to be(false)
    expect(resultado.errores).to include('no se pudo leer el archivo')
  end

  it 'permite cero marcadores con advertencia' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return([])

    resultado = described_class.call(formato: formato, archivo: docx, user: nil)

    expect(resultado.ok?).to be(true)
    expect(resultado.advertencias).not_to be_empty
  end
end
