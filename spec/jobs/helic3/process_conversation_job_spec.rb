# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::ProcessConversationJob do
  let(:client) { instance_double(Helic3::ChatwootClient) }
  let(:runner) { instance_double(Helic3::Agents::RunnerService) }
  let(:memory) { instance_double(Helic3::Agents::ConversationMemory) }
  let(:job) { described_class.new }

  before do
    allow(Helic3::ChatwootClient).to receive(:new).and_return(client)
    allow(Helic3::Agents::RunnerService).to receive(:new).and_return(runner)
    # H3A-08/H3A-12: el job construye el runner, registra el modo y chequea que
    # haya agentes antes de responder. Por defecto: modo clases y con agentes.
    allow(runner).to receive(:modo).and_return(:clases)
    allow(runner).to receive(:hay_agentes?).and_return(true)
    allow(Helic3::Agents::ConversationMemory).to receive(:new).and_return(memory)
    allow(memory).to receive(:load).and_return({})
    allow(memory).to receive(:save)
    allow(client).to receive(:create_message)
    allow(client).to receive(:toggle_typing)
    allow(client).to receive(:update_custom_attributes)
  end

  # H3A-08 criterio 3: sin agentes activos para la bandeja, se deja al humano.
  it 'no responde y deja la conversación al humano cuando no hay agentes activos' do
    allow(runner).to receive(:hay_agentes?).and_return(false)

    expect(runner).not_to receive(:run)
    expect(client).not_to receive(:create_message)

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'corre el runner con el contexto atado a la conversación, publica la respuesta y guarda la memoria' do
    result = instance_double(Agents::RunResult, output: 'Con gusto, te ayudo con eso.', context: { turn_count: 1 })
    expect(runner).to receive(:run)
      .with('hola', context: { account_id: 1,
                               state: { conversation_id: 7, chatwoot_client: client, consentimiento_datos_at: nil } })
      .and_return(result)

    expect(client).to receive(:create_message).with(7, content: 'Con gusto, te ayudo con eso.', message_type: 'outgoing')
    expect(memory).to receive(:save).with({ turn_count: 1 })

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'restaura el hilo previo y lo pasa al runner como contexto' do
    allow(memory).to receive(:load).and_return({ conversation_history: [{ role: :user, content: 'antes' }] })
    expect(runner).to receive(:run)
      .with('hola', context: { conversation_history: [{ role: :user, content: 'antes' }], account_id: 1,
                               state: { conversation_id: 7, chatwoot_client: client, consentimiento_datos_at: nil } })
      .and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
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

  it 'publica un mensaje de derivación cuando el agente escala a un humano sin dejar texto propio' do
    allow(runner).to receive(:run)
      .and_return(instance_double(Agents::RunResult, output: nil, error: nil, context: { state: { escalated: true } }))

    expect(client).to receive(:create_message)
      .with(7, content: described_class::HANDOFF_REPLY, message_type: 'outgoing')

    job.perform(account_id: 1, conversation_id: 7, content: 'quiero hablar con una persona')
  end

  it 'responde con un mensaje de respaldo si el runner no produjo salida' do
    allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: nil, context: {}, error: nil))

    expect(memory).not_to receive(:save)
    expect(client).to receive(:create_message)
      .with(7, content: described_class::FALLBACK_REPLY, message_type: 'outgoing')

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  # H3A-15: estado en vivo por conversación (emitir agente activo + pausa por intervención).
  describe 'estado en vivo (H3A-15)' do
    # crit 1 + B1: el job emite SOLO el agente activo; no reescribe el resto de atributos.
    # Junto con merge: true del cliente (ver chatwoot_client_spec), el sello de consentimiento
    # AGT-07 sobrevive a cada respuesta de la IA.
    it 'emite SOLO el agente que atendió, sin pisar otros atributos como el consentimiento (crit 1/B1)' do
      result = instance_double(Agents::RunResult, output: 'ok', context: { current_agent: 'agente_pqrs' })
      allow(runner).to receive(:run).and_return(result)

      expect(client).to receive(:update_custom_attributes)
        .with(7, { helic3_agente_activo: 'agente_pqrs' })

      job.perform(account_id: 1, conversation_id: 7, content: 'hola')
    end

    describe 'cuando un humano intervino la conversación' do
      let(:account) { create(:account) }
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) do
        create(:conversation, account: account, inbox: inbox,
                              custom_attributes: { 'helic3_ia_pausada' => true })
      end

      it 'no corre el runner ni responde (crit 2)' do
        expect(runner).not_to receive(:run)
        expect(client).not_to receive(:create_message)

        job.perform(account_id: account.id, conversation_id: conversation.display_id, content: 'hola')
      end
    end
  end

  describe 'encolado de la radicación automática (AGT-06)' do
    around do |example|
      original = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
      ActiveJob::Base.queue_adapter = original
    end

    before do
      allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))
    end

    it 'la encola cuando el caso está en manos de PQRS' do
      allow(memory).to receive(:load).and_return({ current_agent: 'agente_pqrs' })

      expect { job.perform(account_id: 1, conversation_id: 7, content: 'mi sofá llegó roto') }
        .to have_enqueued_job(Helic3::RadicarAutomaticoJob)
    end

    it 'la encola TAMBIÉN cuando el caso quedó en FAQ (una garantía puede vivir ahí si el triage no la reenruta)' do
      allow(memory).to receive(:load).and_return({ current_agent: 'agente_faq' })

      expect { job.perform(account_id: 1, conversation_id: 7, content: 'mi mueble de madera se está dañando') }
        .to have_enqueued_job(Helic3::RadicarAutomaticoJob)
    end
  end
end
