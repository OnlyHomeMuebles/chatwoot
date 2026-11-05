# frozen_string_literal: true

require 'rails_helper'

# CFG-01: el servicio de embeddings toma la llave de OpenAI de Super Admin
# (Helic3::Agents::LlmRuntime); sin llave lanza EmbeddingError en vez de heredar
# en silencio la llave global de Captain.
RSpec.describe Helic3::Knowledge::EmbeddingService do
  before { allow(Llm::Config).to receive(:initialize!) }

  describe 'sin llave de OpenAI' do
    it 'lanza EmbeddingError con el mensaje SIN_LLAVE' do
      allow(Helic3::Agents::LlmRuntime).to receive(:api_key).and_return(nil)

      expect { described_class.new.embed('hola') }
        .to raise_error(described_class::EmbeddingError, Helic3::Agents::LlmRuntime::SIN_LLAVE)
    end
  end

  describe 'con llave de OpenAI' do
    it 'arma el contexto con la llave y el endpoint de LlmRuntime' do
      allow(Helic3::Agents::LlmRuntime).to receive(:api_key).and_return('sk-helic3')
      # doubles simples: config y context son internos de RubyLLM, sin una clase
      # publica estable contra la cual verificar.
      # rubocop:disable RSpec/VerifiedDoubles
      config = double('config', :openai_api_key= => nil, :openai_api_base= => nil)
      ctx = double('ctx', embed: double(vectors: [0.1, 0.2]))
      # rubocop:enable RSpec/VerifiedDoubles
      allow(RubyLLM).to receive(:context).and_yield(config).and_return(ctx)

      expect(described_class.new.embed('hola')).to eq([0.1, 0.2])
      expect(config).to have_received(:openai_api_key=).with('sk-helic3')
      expect(config).to have_received(:openai_api_base=).with(Helic3::Agents::LlmRuntime.api_base)
    end
  end
end
