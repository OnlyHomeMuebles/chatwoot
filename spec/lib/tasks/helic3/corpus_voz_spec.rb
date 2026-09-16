# frozen_string_literal: true

require 'rails_helper'
require 'csv'

# AGT-04: el corpus que alimenta el RAG define la VOZ del agente. Estas pruebas
# custodian el corpus (sin depender del LLM): que salga el corpus alienigena de
# software y que entre el de respuestas aprobadas de Only Home, bien formado.
RSpec.describe 'Corpus de voz de Only Home (AGT-04)' do # rubocop:disable RSpec/DescribeClass
  let(:seeds_dir) { Rails.root.join('db/knowledge_seeds') }

  it 'ya no siembra el corpus alienigena de software (casos_servicio_cliente)' do
    expect(File).not_to exist(seeds_dir.join('casos_servicio_cliente.csv'))
  end

  it 'conserva el corpus alienigena como fixture, fuera del sembrado del RAG' do
    expect(File).to exist(Rails.root.join('spec/fixtures/helic3/casos_servicio_cliente.csv'))
  end

  it 'siembra respuestas_aprobadas.csv con la estructura del ticket y al menos 25 filas' do
    path = seeds_dir.join('respuestas_aprobadas.csv')
    expect(File).to exist(path)

    rows = CSV.read(path, headers: true)
    expect(rows.headers).to eq(%w[situacion respuesta_aprobada canal notas])
    expect(rows.size).to be >= 25
    expect(rows).to all(satisfy { |r| r['situacion'].present? && r['respuesta_aprobada'].present? })
  end

  it 'el corpus de voz no trae vocabulario de software ajeno a Only Home' do
    texto = File.read(seeds_dir.join('respuestas_aprobadas.csv')).downcase
    expect(texto).not_to match(/\bstarter\b|\bfree plan\b|subscription|suscripci[oó]n|\bplan (starter|free)\b|\$\d/)
  end

  it 'cubre las situaciones canonicas que pide el ticket' do
    texto = File.read(seeds_dir.join('respuestas_aprobadas.csv')).downcase
    %w[saludo garantia pieza retracto pedido horario precio].each do |tema|
      expect(texto).to include(tema)
    end
  end
end
