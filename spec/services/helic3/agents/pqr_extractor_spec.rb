# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::PqrExtractor do
  let(:account) { create(:account) }
  let(:extractor) { described_class.new(account: account, api_key: 'test-key') }

  let(:chat) { instance_double(RubyLLM::Chat) }

  before do
    Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo')
    garantia = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto',
                                        codigo: 'garantia_producto', categoria: garantia)

    allow(chat).to receive(:with_temperature)
    allow(chat).to receive(:with_instructions)
    allow(chat).to receive(:with_params)
    context = instance_double(RubyLLM::Context, chat: chat)
    allow(Llm::Config).to receive(:with_api_key).and_yield(context)
  end

  def responde_con(json)
    allow(chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: json))
  end

  it 'parsea una clasificación válida de PQR' do
    responde_con(
      { requiere_pqr: true, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
        resumen: 'Sofá roto', descripcion: 'Llegó roto', numero_orden: '345670' }.to_json
    )

    resultado = extractor.call('Cliente: mi sofá llegó roto, factura 345670')

    expect(resultado.requiere_pqr).to be(true)
    expect(resultado.tipo_codigo).to eq('reclamo')
    expect(resultado.motivo_codigo).to eq('garantia_producto')
    expect(resultado.numero_orden).to eq('345670')
  end

  it 'cuando no requiere PQR, ignora el resto' do
    responde_con({ requiere_pqr: false }.to_json)

    resultado = extractor.call('Cliente: hola, ¿tienen envíos a Cartagena?')

    expect(resultado.requiere_pqr).to be(false)
    expect(resultado.tipo_codigo).to be_nil
  end

  it 'devuelve nil ante un JSON inválido (se trata como sin señal)' do
    responde_con('esto no es json')

    expect(extractor.call('Cliente: algo')).to be_nil
  end

  it 'no llama al LLM si el texto viene vacío' do
    expect(Llm::Config).not_to receive(:with_api_key)
    expect(extractor.call('')).to be_nil
  end
end
