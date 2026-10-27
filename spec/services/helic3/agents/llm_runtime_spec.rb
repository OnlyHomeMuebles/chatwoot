# frozen_string_literal: true

require 'rails_helper'

# CFG-01: unico proveedor OpenAI; la llave sale de Super Admin
# (installation_configs, HELIC3_OPENAI_API_KEY), nunca del entorno ni de Captain.
RSpec.describe Helic3::Agents::LlmRuntime do
  before { GlobalConfig.clear_cache }

  after { GlobalConfig.clear_cache }

  describe '.api_key' do
    it 'sale de HELIC3_OPENAI_API_KEY en Super Admin' do
      InstallationConfig.create!(name: 'HELIC3_OPENAI_API_KEY', value: 'sk-helic3', locked: false)
      GlobalConfig.clear_cache

      expect(described_class.api_key).to eq('sk-helic3')
    end

    it 'es nil cuando no hay registro' do
      expect(described_class.api_key).to be_nil
    end

    it 'NO lee OPENAI_API_KEY del entorno ni la llave de Captain' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('sk-del-entorno')
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'sk-captain', locked: false)
      GlobalConfig.clear_cache

      expect(described_class.api_key).to be_nil
    end
  end

  describe '.api_base' do
    it 'es el endpoint de OpenAI explicito (no hereda el de Captain)' do
      expect(described_class.api_base).to eq("#{LlmConstants::OPENAI_API_ENDPOINT}/v1")
    end
  end

  describe '.agents_options' do
    it 'siempre usa provider :openai con assume_model_exists' do
      opts = described_class.agents_options

      expect(opts[:provider]).to eq(:openai)
      expect(opts[:assume_model_exists]).to be(true)
      expect(opts[:model]).to eq(described_class.model)
    end
  end

  describe '.model (sin cambios respecto a antes de CFG-01)' do
    it 'se puede cambiar desde Super Admin con CAPTAIN_OPEN_AI_MODEL' do
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-super', locked: false)

      expect(described_class.model).to eq('gpt-super')
    end

    it 'cae al default del sistema sin configuracion' do
      expect(described_class.model).to eq(LlmConstants::DEFAULT_MODEL)
    end
  end

  describe '.configure_agents!' do
    # double simple: el objeto que yield Agents.configure es interno del gem
    # ai-agents, sin una clase publica estable contra la cual verificar.
    # rubocop:disable RSpec/VerifiedDoubles
    let(:config) do
      double('agents_config', :openai_api_key= => nil, :openai_api_base= => nil)
    end
    # rubocop:enable RSpec/VerifiedDoubles

    before { allow(Agents).to receive(:configure).and_yield(config) }

    it 'registra el error y deja la llave nil cuando no hay llave' do
      expect(Rails.logger).to receive(:error).with(described_class::SIN_LLAVE)

      described_class.configure_agents!

      expect(config).to have_received(:openai_api_key=).with(nil)
      expect(config).to have_received(:openai_api_base=).with(described_class::API_BASE)
    end

    it 'fija la llave vigente y el API_BASE cuando hay llave' do
      InstallationConfig.create!(name: 'HELIC3_OPENAI_API_KEY', value: 'sk-helic3', locked: false)
      GlobalConfig.clear_cache

      described_class.configure_agents!

      expect(config).to have_received(:openai_api_key=).with('sk-helic3')
      expect(config).to have_received(:openai_api_base=).with(described_class::API_BASE)
    end
  end
end
