# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::Copilot::SuggestionService do
  subject(:service) { described_class.new(model: 'gpt-4.1-mini') }

  let(:mock_runner) { instance_double(Agents::AgentRunner) }

  before { allow(Agents::Runner).to receive(:with_agents).and_return(mock_runner) }

  it 'corre el copiloto con el contexto de la conversación y devuelve la sugerencia' do
    expect(mock_runner).to receive(:run)
      .with('redáctame una respuesta para el cliente', context: { state: { conversation_id: 7 } })
      .and_return(instance_double(Agents::RunResult, output: 'Podrías responder: "Lamento el inconveniente..."'))

    expect(service.suggest(conversation_id: 7, query: 'redáctame una respuesta para el cliente'))
      .to eq('Podrías responder: "Lamento el inconveniente..."')
  end

  it 'incluye el historial previo del copiloto cuando se pasa' do
    history = [{ role: :user, content: 'resume el caso' }]
    expect(mock_runner).to receive(:run)
      .with('ahora redacta la respuesta', context: { state: { conversation_id: 7 }, conversation_history: history })
      .and_return(instance_double(Agents::RunResult, output: 'ok'))

    service.suggest(conversation_id: 7, query: 'ahora redacta la respuesta', history: history)
  end

  it 'usa el agente copiloto como agente de entrada del runner' do
    allow(mock_runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: 'x'))
    expect(Agents::Runner).to receive(:with_agents) do |agent|
      expect(agent.name).to eq('copiloto_only_home')
      mock_runner
    end

    service.suggest(conversation_id: 7, query: 'hola')
  end
end
