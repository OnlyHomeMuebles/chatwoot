# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::CatalogoHerramientas do
  describe '.instanciar (autorizacion por agente, H3A-10)' do
    # se comparan las CLASES (no .class.name: RubyLLM::Tool sobreescribe name con el
    # nombre que ve el LLM, p. ej. "search_knowledge_base").
    def clases(tools)
      tools.map(&:class)
    end

    it 'inyecta SIEMPRE derivar_humano, aunque no este en las claves del agente' do
      tools = described_class.instanciar(%w[buscar_conocimiento])
      expect(clases(tools)).to include(Helic3::Agents::Tools::HumanHandoffTool)
    end

    it 'derivar_humano va primero (paridad con las clases)' do
      tools = described_class.instanciar(%w[buscar_conocimiento])
      expect(clases(tools).first).to eq(Helic3::Agents::Tools::HumanHandoffTool)
    end

    # crit 1: un agente SIN radicar_pqr no recibe la herramienta, asi que no puede
    # radicar aunque el prompt se lo pida (el modelo solo puede llamar tools que tiene).
    it 'un agente sin radicar_pqr NO recibe la herramienta de radicar' do
      tools = described_class.instanciar(%w[buscar_conocimiento])
      expect(clases(tools)).not_to include(Helic3::Agents::Tools::RadicarPqrTool)
    end

    it 'un agente CON radicar_pqr si la recibe' do
      tools = described_class.instanciar(%w[buscar_conocimiento radicar_pqr])
      expect(clases(tools)).to include(Helic3::Agents::Tools::RadicarPqrTool)
    end

    it 'ignora una clave desconocida (defensa)' do
      tools = described_class.instanciar(%w[buscar_conocimiento clave_inventada])
      expect(clases(tools)).to contain_exactly(
        Helic3::Agents::Tools::HumanHandoffTool, Helic3::KnowledgeBaseSearchTool
      )
    end
  end
end
