# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::TriageAgent do
  describe '.build' do
    subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

    it 'tiene el nombre correcto' do
      expect(agent.name).to eq('agente_triage')
    end

    it 'lleva la herramienta de escalamiento a humano (para pedidos explícitos o casos sensibles)' do
      expect(agent.tools.map { |t| t.class.name }).to include('OnlyHome::Tools::HumanHandoffTool')
    end

    it 'sus instrucciones contemplan escalar cuando el cliente pide un humano' do
      expect(described_class::INSTRUCTIONS).to include('herramienta de escalamiento')
    end

    it 'sus instrucciones mencionan los cuatro dominios' do
      expect(described_class::INSTRUCTIONS).to include('agente_faq')
      expect(described_class::INSTRUCTIONS).to include('agente_pqrs')
      expect(described_class::INSTRUCTIONS).to include('agente_logistica')
      expect(described_class::INSTRUCTIONS).to include('agente_cotizaciones')
    end

    it 'sus instrucciones prohíben resolver directamente' do
      expect(described_class::INSTRUCTIONS).to include('No resuelves')
    end
  end

  describe 'registro de handoffs' do
    let(:triage)       { described_class.build(model: 'gpt-4.1-mini') }
    let(:faq)          { OnlyHome::FaqAgent.build(model: 'gpt-4.1-mini') }
    let(:pqrs)         { OnlyHome::PqrsAgent.build(model: 'gpt-4.1-mini') }
    let(:logistica)    { OnlyHome::LogisticaAgent.build(model: 'gpt-4.1-mini') }
    let(:cotizaciones) { OnlyHome::CotizacionesAgent.build(model: 'gpt-4.1-mini') }

    before { triage.register_handoffs(faq, pqrs, logistica, cotizaciones) }

    it 'puede transferir a los cuatro especialistas' do
      nombres = triage.handoff_agents.map(&:name)
      expect(nombres).to include('agente_faq', 'agente_pqrs', 'agente_logistica', 'agente_cotizaciones')
    end

    it 'no tiene handoff hacia sí mismo (sin bucles)' do
      expect(triage.handoff_agents.map(&:name)).not_to include('agente_triage')
    end
  end
end
