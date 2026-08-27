# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::PqrsAgent do
  subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

  it 'se construye como el especialista de PQRS y garantías' do
    expect(agent.name).to eq('agente_pqrs')
    expect(agent.model).to eq('gpt-4.1-mini')
  end

  describe 'instrucciones base' do
    it 'delimitan su responsabilidad a la gestión postventa' do
      expect(described_class::INSTRUCTIONS).to match(/postventa/i)
      expect(described_class::INSTRUCTIONS).to match(/garantía/i)
    end

    it 'prioriza dar siempre una solución concreta al cliente' do
      expect(described_class::INSTRUCTIONS).to match(/siempre una solución/i)
    end

    it 'da tiempos reales de garantía y no inventa números de ticket' do
      expect(described_class::INSTRUCTIONS).to match(/12 a 15 días/i)
      expect(described_class::INSTRUCTIONS).to match(/inventes un número de ticket/i)
    end
  end

  describe 'instrucciones dinámicas por contexto' do
    it 'inyecta el cliente y el número de orden cuando están en el contexto' do
      prompt = agent.get_system_prompt(
        Agents::RunContext.new({ state: { customer_name: 'Carlos Díaz', order_number: 'ORD-9988' } })
      )

      expect(prompt).to include('Contexto de la conversación')
      expect(prompt).to include('Carlos Díaz')
      expect(prompt).to include('ORD-9988')
    end

    it 'usa solo las instrucciones base cuando no hay contexto' do
      prompt = agent.get_system_prompt(Agents::RunContext.new({}))

      expect(prompt).to eq(described_class::INSTRUCTIONS)
    end
  end
end
