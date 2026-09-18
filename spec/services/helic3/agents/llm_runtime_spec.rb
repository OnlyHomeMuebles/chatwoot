# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::LlmRuntime do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(InstallationConfig).to receive(:find_by).and_call_original
    %w[ONLY_HOME_LLM_PROVIDER GEMINI_API_KEY OPENAI_API_KEY GROQ_API_KEY ONLY_HOME_OPENAI_MODEL]
      .each { |k| allow(ENV).to receive(:[]).with(k).and_return(nil) }
  end

  def env(key, value)
    allow(ENV).to receive(:[]).with(key).and_return(value)
  end

  describe '.provider' do
    it 'respeta el proveedor explicito de ONLY_HOME_LLM_PROVIDER' do
      env('ONLY_HOME_LLM_PROVIDER', 'groq')
      expect(described_class.provider).to eq(:groq)
    end

    it 'elige gemini cuando hay GEMINI_API_KEY' do
      env('GEMINI_API_KEY', 'g-key')
      expect(described_class.provider).to eq(:gemini)
    end

    it 'elige openai cuando solo hay OPENAI_API_KEY' do
      env('OPENAI_API_KEY', 'o-key')
      expect(described_class.provider).to eq(:openai)
    end

    it 'cae a ollama sin ninguna credencial' do
      expect(described_class.provider).to eq(:ollama)
    end
  end

  describe '.agents_options' do
    it 'mapea gemini al provider :openai (endpoint compatible) con assume_model_exists' do
      env('GEMINI_API_KEY', 'g-key')
      opts = described_class.agents_options
      expect(opts[:provider]).to eq(:openai)
      expect(opts[:assume_model_exists]).to be(true)
    end

    it 'mantiene :ollama como provider propio' do
      expect(described_class.agents_options[:provider]).to eq(:ollama)
    end
  end

  describe '.model del proveedor OpenAI' do
    before { env('OPENAI_API_KEY', 'o-key') }

    it 'se puede cambiar desde Super Admin con CAPTAIN_OPEN_AI_MODEL' do
      allow(InstallationConfig).to receive(:find_by).with(name: 'CAPTAIN_OPEN_AI_MODEL')
                                                    .and_return(instance_double(InstallationConfig, value: 'gpt-super'))
      expect(described_class.model).to eq('gpt-super')
    end
  end

  describe '.api_key' do
    it 'para ollama devuelve una credencial ficticia (cliente local sin llave)' do
      expect(described_class.api_key(:ollama)).to eq('ollama')
    end

    it 'para gemini devuelve la llave de Gemini' do
      env('GEMINI_API_KEY', 'g-key')
      expect(described_class.api_key(:gemini)).to eq('g-key')
    end
  end
end
