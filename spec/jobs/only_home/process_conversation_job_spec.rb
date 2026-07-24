# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::ProcessConversationJob do
  let(:client) { instance_double(OnlyHome::ChatwootClient) }
  let(:runner) { instance_double(OnlyHome::RunnerService) }

  before do
    allow(OnlyHome::ChatwootClient).to receive(:new).and_return(client)
    allow(OnlyHome::RunnerService).to receive(:new).and_return(runner)
    allow(client).to receive(:create_message)
  end

  it 'corre el runner con el contexto atado a la conversación y publica la respuesta del agente' do
    expect(runner).to receive(:run)
      .with('hola', context: { state: { conversation_id: 7, chatwoot_client: client } })
      .and_return(instance_double(Agents::RunResult, output: 'Con gusto, te ayudo con eso.'))

    expect(client).to receive(:create_message).with(7, content: 'Con gusto, te ayudo con eso.', message_type: 'outgoing')

    described_class.perform_now(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'no publica nada si el runner no produjo salida' do
    allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: nil))

    expect(client).not_to receive(:create_message)

    described_class.perform_now(account_id: 1, conversation_id: 7, content: 'hola')
  end
end
