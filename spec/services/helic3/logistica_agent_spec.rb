# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::LogisticaAgent do
  subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

  it 'se construye como el especialista de logística' do
    expect(agent.name).to eq('agente_logistica')
    expect(agent.model).to eq('gpt-4.1-mini')
  end

  describe 'instrucciones base' do
    it 'delimitan su responsabilidad a la operación de entrega' do
      expect(described_class::INSTRUCTIONS).to match(/estado de pedidos/i)
      expect(described_class::INSTRUCTIONS).to match(/transportadoras/i)
    end

    it 'declaran las fronteras (no PQRS, cotizaciones ni FAQ)' do
      expect(described_class::INSTRUCTIONS).to match(/No gestionas quejas/i)
      expect(described_class::INSTRUCTIONS).to match(/No generas precios/i)
    end

    it 'devuelve el control al triage fuera de su dominio' do
      expect(described_class::INSTRUCTIONS).to include('agente_triage')
    end
  end

  describe 'instrucciones dinámicas por contexto' do
    it 'inyecta el cliente y el número de pedido cuando están en el contexto' do
      prompt = agent.get_system_prompt(
        Agents::RunContext.new({ state: { customer_name: 'Ana Ruiz', order_number: 'PED-12345' } })
      )

      expect(prompt).to include('Contexto de la conversación')
      expect(prompt).to include('Ana Ruiz')
      expect(prompt).to include('PED-12345')
    end

    it 'usa solo las instrucciones base cuando no hay contexto' do
      prompt = agent.get_system_prompt(Agents::RunContext.new({}))

      expect(prompt).to eq(described_class::INSTRUCTIONS)
    end
  end
end
