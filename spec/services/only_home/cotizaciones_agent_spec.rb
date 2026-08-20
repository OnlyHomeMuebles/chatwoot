# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::CotizacionesAgent do
  subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

  it 'se construye como el especialista de cotizaciones' do
    expect(agent.name).to eq('agente_cotizaciones')
    expect(agent.model).to eq('gpt-4.1-mini')
  end

  describe 'instrucciones base' do
    it 'delimitan su responsabilidad a la etapa comercial previa a la compra' do
      expect(described_class::INSTRUCTIONS).to match(/cotizaci/i)
      expect(described_class::INSTRUCTIONS).to match(/COP/)
    end

    it 'declaran las fronteras (no PQRS, logística ni FAQ)' do
      expect(described_class::INSTRUCTIONS).to match(/No gestionas quejas/i)
      expect(described_class::INSTRUCTIONS).to match(/No consultas el estado/i)
    end

    it 'devuelve el control al triage fuera de su dominio' do
      expect(described_class::INSTRUCTIONS).to include('agente_triage')
    end
  end

  describe 'instrucciones dinámicas por contexto' do
    it 'inyecta cliente, ciudad y producto de interés cuando están en el contexto' do
      prompt = agent.get_system_prompt(
        Agents::RunContext.new({ state: { customer_name: 'Laura Gómez', city: 'Medellín', product: 'cocina integral' } })
      )

      expect(prompt).to include('Contexto de la conversación')
      expect(prompt).to include('Laura Gómez')
      expect(prompt).to include('Medellín')
      expect(prompt).to include('cocina integral')
    end

    it 'usa solo las instrucciones base cuando no hay contexto' do
      prompt = agent.get_system_prompt(Agents::RunContext.new({}))

      expect(prompt).to eq(described_class::INSTRUCTIONS)
    end
  end
end
