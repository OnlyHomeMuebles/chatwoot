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
    allow(Helic3::Agents::ConversationMemory).to receive(:new).and_return(memory)
    allow(memory).to receive(:load).and_return({})
    allow(memory).to receive(:save)
    allow(client).to receive(:create_message)
    allow(client).to receive(:toggle_typing)
    # AGT-08: sin imagenes no hay nada que leer; cada test que las manda stubea su propio resultado.
    allow(Helic3::Agents::LectorDeImagenes).to receive(:leer).and_return(nil)
  end

  it 'corre el runner con el contexto atado a la conversación, publica la respuesta y guarda la memoria' do
    result = instance_double(Agents::RunResult, output: 'Con gusto, te ayudo con eso.', context: { turn_count: 1 })
    expect(runner).to receive(:run)
      .with('hola', context: { account_id: 1,
                               state: { conversation_id: 7, chatwoot_client: client, consentimiento_datos_at: nil,
                                        imagenes: [], texto_imagenes: nil } })
      .and_return(result)

    expect(client).to receive(:create_message).with(7, content: 'Con gusto, te ayudo con eso.', message_type: 'outgoing')
    expect(memory).to receive(:save).with({ turn_count: 1 })

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'restaura el hilo previo y lo pasa al runner como contexto' do
    allow(memory).to receive(:load).and_return({ conversation_history: [{ role: :user, content: 'antes' }] })
    expect(runner).to receive(:run)
      .with('hola', context: { conversation_history: [{ role: :user, content: 'antes' }], account_id: 1,
                               state: { conversation_id: 7, chatwoot_client: client, consentimiento_datos_at: nil,
                                        imagenes: [], texto_imagenes: nil } })
      .and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

    job.perform(account_id: 1, conversation_id: 7, content: 'hola')
  end

  it 'lee el texto de las imagenes (AGT-08, determinista) y lo suma al state' do
    fotos = ['https://cdn.chatwoot.test/factura.jpg']
    allow(Helic3::Agents::LectorDeImagenes).to receive(:leer).with(fotos).and_return('Factura N.° 8821')
    expect(runner).to receive(:run)
      .with('hola', context: { account_id: 1,
                               state: { conversation_id: 7, chatwoot_client: client, consentimiento_datos_at: nil,
                                        imagenes: fotos, texto_imagenes: 'Factura N.° 8821' } })
      .and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

    job.perform(account_id: 1, conversation_id: 7, content: 'hola', imagenes: fotos)
  end

  it 'usa un mensaje de respaldo para el runner cuando el cliente solo mandó una foto (sin texto)' do
    fotos = ['https://cdn.chatwoot.test/foto-dano.jpg']
    expect(runner).to receive(:run)
      .with(described_class::SOLO_IMAGEN_CONTENT,
            context: { account_id: 1,
                       state: { conversation_id: 7, chatwoot_client: client, consentimiento_datos_at: nil,
                                imagenes: fotos, texto_imagenes: nil } })
      .and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

    job.perform(account_id: 1, conversation_id: 7, content: '', imagenes: fotos)
  end

  # B3 (revision de Jhan, 23-sep): antes, un adjunto que no es imagen (nota de
  # voz, PDF, ubicacion) sin texto dejaba mensaje = "" y el runner se invocaba
  # con una cadena vacia. Las notas de voz son muy frecuentes en WhatsApp.
  it 'usa un mensaje de respaldo para el runner cuando el cliente solo mandó una nota de voz (sin texto ni imagenes)' do
    expect(runner).to receive(:run)
      .with(described_class::SOLO_ADJUNTO_CONTENT,
            context: { account_id: 1,
                       state: { conversation_id: 7, chatwoot_client: client, consentimiento_datos_at: nil,
                                imagenes: [], texto_imagenes: nil } })
      .and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

    job.perform(account_id: 1, conversation_id: 7, content: '', imagenes: [], hay_adjuntos: true)
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
