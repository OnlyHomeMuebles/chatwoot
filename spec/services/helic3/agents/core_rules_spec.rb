# frozen_string_literal: true

require 'rails_helper'

# Fija la regla de AGT-guardrails: TODOS los agentes deben llevar los guardrails
# base (Core Rules) en su prompt renderizado. Es un criterio de presencia, no de
# comportamiento del modelo: no llamamos al LLM (no determinista), verificamos
# que las reglas esten inyectadas. Si un refactor futuro le quita las reglas a
# un agente, este spec falla.
RSpec.describe Helic3::Agents::CoreRules do
  let(:account) { create(:account) }
  let(:contexto) { Agents::RunContext.new({ account_id: account.id }) }

  [
    Helic3::Agents::TriageAgent,
    Helic3::Agents::FaqAgent,
    Helic3::Agents::LogisticaAgent,
    Helic3::Agents::CotizacionesAgent,
    Helic3::Agents::PqrsAgent
  ].each do |klass|
    it "#{klass} incluye los guardrails base en su system prompt" do
      prompt = klass.build(model: 'gpt-4.1-mini').get_system_prompt(contexto)

      expect(prompt).to include('Stay inside your specialty')
      expect(prompt).to include('Ground every factual statement')
      expect(prompt).to include('<untrusted_data>')
    end
  end

  it 'define las cinco reglas como una sola fuente compartida' do
    expect(described_class::GUIDE).to include('# Core Rules:')
    # las cinco reglas empiezan con "- " (una linea por regla)
    expect(described_class::GUIDE.scan(/^- /).size).to eq(5)
  end
end
