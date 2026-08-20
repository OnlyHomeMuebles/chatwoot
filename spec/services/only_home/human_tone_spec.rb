# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::HumanTone do
  it 'define una guía de tono humano y no robótico' do
    expect(described_class::GUIDE).to match(/no como un robot/i)
    expect(described_class::GUIDE).to match(/empátic/i)
    expect(described_class::GUIDE).to match(/natural/i)
  end

  it 'todos los agentes incorporan el tono humano en sus instrucciones' do
    agentes = [
      OnlyHome::TriageAgent, OnlyHome::FaqAgent, OnlyHome::PqrsAgent,
      OnlyHome::LogisticaAgent, OnlyHome::CotizacionesAgent, OnlyHome::Copilot::Agent
    ]
    agentes.each do |agente|
      expect(agente::INSTRUCTIONS).to include('Tono y estilo'), "#{agente} no incorpora el tono humano"
    end
  end
end
