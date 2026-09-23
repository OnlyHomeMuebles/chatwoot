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

  # H3A-11: límites de ejecución del agente activo antes de responder.
  describe 'límites de ejecución (H3A-11)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:team) { create(:team, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:agente) do
      Helic3::Agente.create!(account: account, codigo: 'agente_triage', nombre: 'T', es_sistema: true,
                             prompt: 'p', max_respuestas: 3, team_id: team.id, mensaje_handoff: 'Te paso con un asesor 💙')
    end

    before do
      Helic3::AgenteBandeja.create!(agente: agente, inbox: inbox)
      allow(client).to receive(:assign)
    end

    it 'al llegar al tope de respuestas deriva al equipo con el mensaje_handoff, sin correr el runner (crit 1)' do
      allow(memory).to receive(:load).and_return({ current_agent: 'agente_triage', turn_count: 3 })

      expect(runner).not_to receive(:run)
      expect(client).to receive(:create_message)
        .with(conversation.display_id, content: 'Te paso con un asesor 💙', message_type: 'outgoing')
      expect(client).to receive(:assign).with(conversation.display_id, team_id: team.id)

      job.perform(account_id: account.id, conversation_id: conversation.display_id, content: 'sigo molesto')
    end

    it 'fuera de horario no responde ni corre el runner: queda sin IA (crit 2)' do
      allow_any_instance_of(Helic3::Agents::LimitesService).to receive(:evaluar) # rubocop:disable RSpec/AnyInstance
        .and_return(Helic3::Agents::LimitesService::Decision.new(accion: :dejar_sin_ia, motivo: 'fuera del horario de atención'))

      expect(runner).not_to receive(:run)
      expect(client).not_to receive(:create_message)

      job.perform(account_id: account.id, conversation_id: conversation.display_id, content: 'hola')
    end

    it 'dentro de límites, corre el runner normalmente' do
      allow(memory).to receive(:load).and_return({ current_agent: 'agente_triage', turn_count: 1 })
      allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

      expect(runner).to receive(:run)

      job.perform(account_id: account.id, conversation_id: conversation.display_id, content: 'hola')
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
