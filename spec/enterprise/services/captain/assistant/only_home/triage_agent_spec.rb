# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Assistant::OnlyHome::TriageAgent do
  describe '.build' do
    subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

    it 'tiene el nombre correcto' do
      expect(agent.name).to eq('agente_triage')
    end

    it 'no tiene tools propias (solo enruta)' do
      expect(Array(agent.tools)).to be_empty
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
    let(:faq)          { Captain::Assistant::OnlyHome::FaqAgent.build(model: 'gpt-4.1-mini') }
    let(:pqrs)         { Captain::Assistant::OnlyHome::PqrsAgent.build(model: 'gpt-4.1-mini') }
    let(:logistica)    { Captain::Assistant::OnlyHome::LogisticaAgent.build(model: 'gpt-4.1-mini') }
    let(:cotizaciones) { Captain::Assistant::OnlyHome::CotizacionesAgent.build(model: 'gpt-4.1-mini') }

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
