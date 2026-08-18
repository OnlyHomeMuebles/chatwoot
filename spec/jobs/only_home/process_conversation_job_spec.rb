# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::ProcessConversationJob do
  let(:client) { instance_double(OnlyHome::ChatwootClient) }
  let(:runner) { instance_double(OnlyHome::RunnerService) }
  let(:memory) { instance_double(OnlyHome::ConversationMemory) }
  let(:job) { described_class.new }

  before do
    allow(OnlyHome::ChatwootClient).to receive(:new).and_return(client)
    allow(OnlyHome::RunnerService).to receive(:new).and_return(runner)
    allow(OnlyHome::ConversationMemory).to receive(:new).and_return(memory)
    allow(memory).to receive(:load).and_return({})
    allow(memory).to receive(:save)
    allow(client).to receive(:create_message)
    allow(client).to receive(:toggle_typing)
    # Por defecto, modo multiagente (sin RAG local) para tests deterministas y sin dependencias externas.
    allow(job).to receive(:single_mode?).and_return(false)
  end

  it 'corre el runner con el contexto atado a la conversación, publica la respuesta y guarda la memoria' do
    result = instance_double(Agents::RunResult, output: 'Con gusto, te ayudo con eso.', context: { turn_count: 1 })
    expect(runner).to receive(:run)
      .with('hola', context: { account_id: 1, state: { conversation_id: 7, chatwoot_client: client, knowledge: nil } })
      .and_return(result)

    expect(client).to receive(:create_message).with(7, content: 'Con gusto, te ayudo con eso.', message_type: 'outgoing')
    expect(memory).to receive(:save).with({ turn_count: 1 })

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'restaura el hilo previo y lo pasa al runner como contexto' do
    allow(memory).to receive(:load).and_return({ conversation_history: [{ role: :user, content: 'antes' }] })
    expect(runner).to receive(:run)
      .with('hola', context: { conversation_history: [{ role: :user, content: 'antes' }], account_id: 1,
                               state: { conversation_id: 7, chatwoot_client: client, knowledge: nil } })
      .and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'en modo local (RAG) recupera conocimiento y lo inyecta en el contexto del agente único' do
    allow(job).to receive(:single_mode?).and_return(true)
    allow(OnlyHome::KnowledgeRetriever).to receive(:context_for).with('¿garantía?').and_return('Garantía: 10 años en madera.')
    expect(OnlyHome::RunnerService).to receive(:new).with(hash_including(single: true)).and_return(runner)
    expect(runner).to receive(:run)
      .with('¿garantía?', context: { account_id: 1,
                                     state: { conversation_id: 7, chatwoot_client: client, knowledge: 'Garantía: 10 años en madera.' } })
      .and_return(instance_double(Agents::RunResult, output: 'Sí, 10 años.', context: {}))

    job.perform(account_id: 1, conversation_id: 7, content: '¿garantía?')
  end

  it 'muestra el indicador de escritura y lo apaga al terminar' do
    allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

    expect(client).to receive(:toggle_typing).with(7, on: true).ordered
    expect(client).to receive(:toggle_typing).with(7, on: false).ordered

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'reintenta ante un error de cuota/tasa y responde cuando el segundo intento tiene éxito' do
    allow(job).to receive(:sleep)
    rate_limited = instance_double(Agents::RunResult, output: nil, context: {},
                                                      error: RuntimeError.new('You exceeded your current quota. Please retry in 2s.'))
    ok = instance_double(Agents::RunResult, output: 'Aquí está la info 💙', context: { turn_count: 1 })
    allow(runner).to receive(:run).and_return(rate_limited, ok)

    expect(client).to receive(:create_message).with(7, content: 'Aquí está la info 💙', message_type: 'outgoing')
    expect(memory).to receive(:save).with({ turn_count: 1 })

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'responde con un mensaje de respaldo si el runner falla, sin guardar memoria' do
    allow(runner).to receive(:run).and_raise(StandardError, 'boom')

    expect(memory).not_to receive(:save)
    expect(client).to receive(:create_message)
      .with(7, content: described_class::FALLBACK_REPLY, message_type: 'outgoing')

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'responde con un mensaje de respaldo si el runner no produjo salida' do
    allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: nil, context: {}, error: nil))

    expect(memory).not_to receive(:save)
    expect(client).to receive(:create_message)
      .with(7, content: described_class::FALLBACK_REPLY, message_type: 'outgoing')

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end
end
