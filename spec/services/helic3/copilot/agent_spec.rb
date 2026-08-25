# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Copilot::Agent do
  subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

  it 'se construye como el copiloto de Only Home' do
    expect(agent.name).to eq('copiloto_helic3')
    expect(agent.model).to eq('gpt-4.1-mini')
  end

  it 'asiste al agente humano y no le escribe al cliente' do
    expect(described_class::INSTRUCTIONS).to match(/AGENTE HUMANO/)
    expect(described_class::INSTRUCTIONS).to match(/no envías nada al cliente/i)
  end

  it 'incluye la herramienta para leer la conversación' do
    expect(agent.tools.map(&:class)).to include(Helic3::Tools::GetConversationTool)
  end
end
