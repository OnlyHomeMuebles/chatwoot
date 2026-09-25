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
    # AGT-08: sin imagenes no hay nada que leer; cada test que las manda stubea su propio resultado.
    allow(Helic3::Agents::LectorDeImagenes).to receive(:leer).and_return(nil)
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

  # H3A-15: estado en vivo por conversación (emitir agente activo + guard por estado, B4).
  describe 'estado en vivo (H3A-15)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }

    # crit 1 + B1: el job emite SOLO el agente activo; no reescribe el resto de atributos.
    # Junto con merge: true del cliente, el sello de consentimiento (AGT-07) sobrevive.
    it 'emite SOLO el agente que atendió, sin pisar otros atributos como el consentimiento (crit 1/B1)' do
      result = instance_double(Agents::RunResult, output: 'ok', context: { current_agent: 'agente_pqrs' })
      allow(runner).to receive(:run).and_return(result)

      expect(client).to receive(:update_custom_attributes)
        .with(7, { helic3_agente_activo: 'agente_pqrs' })

      job.perform(account_id: 1, conversation_id: 7, content: 'hola')
    end

    # B4 (revisión de Jhan): el guard mira el ESTADO, no una bandera que nunca se limpia.
    it 'no corre el runner ni responde cuando la conversación ya no está en pending (crit 2/B4)' do
      conv = create(:conversation, account: account, inbox: inbox, status: :open)

      expect(runner).not_to receive(:run)
      expect(client).not_to receive(:create_message)

      job.perform(account_id: account.id, conversation_id: conv.display_id, content: 'hola')
    end

    # B4: intervenida -> resuelta -> reabierta en pending: la IA vuelve a responder
    # (aunque la marca de auditoría helic3_intervenido_at siga puesta).
    it 'responde de nuevo si una conversación intervenida se reabre en pending (crit 3/B4)' do
      conv = create(:conversation, account: account, inbox: inbox, status: :pending,
                                   custom_attributes: { 'helic3_intervenido_at' => '2026-09-01T00:00:00Z' })
      allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))

      expect(runner).to receive(:run)

      job.perform(account_id: account.id, conversation_id: conv.display_id, content: 'volví')
    end
  end

  # H3A-11: límites de ejecución del agente activo antes de responder.
  describe 'límites de ejecución (H3A-11)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:team) { create(:team, account: account) }
    # pending = territorio del bot (el job solo corre ahí, B4)
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
    let!(:agente) do
      Helic3::Agente.create!(account: account, codigo: 'agente_triage', nombre: 'T', es_sistema: true,
                             prompt: 'p', max_respuestas: 3, team_id: team.id, mensaje_handoff: 'Te paso con un asesor 💙')
    end

    before do
      Helic3::AgenteBandeja.create!(agente: agente, inbox: inbox)
      allow(client).to receive(:assign)
      allow(client).to receive(:update_status)
    end

    it 'al llegar al tope de respuestas deriva al equipo con el mensaje_handoff, sin correr el runner (crit 1)' do
      allow(memory).to receive(:load).and_return({ current_agent: 'agente_triage', turn_count: 3 })

      expect(runner).not_to receive(:run)
      expect(client).to receive(:create_message)
        .with(conversation.display_id, content: 'Te paso con un asesor 💙', message_type: 'outgoing')
      expect(client).to receive(:assign).with(conversation.display_id, team_id: team.id)
      # B1: además saca la conversación de 'pending' -> el webhook deja de encolar el job
      # (ver webhook_handler_spec: una conversación 'open' no se procesa), así el segundo
      # mensaje del cliente NO vuelve a recibir el handoff.
      expect(client).to receive(:update_status).with(conversation.display_id, 'open')

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

  # H3A-17 (determinista): en una garantía sin datos del titular, el SISTEMA los pide una sola vez.
  # pending = territorio del bot (el guard B4 exige que el job solo corra ahí)
  describe 'solicitud determinista de datos del cliente (H3A-17)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
    let(:garantia) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia') }
    let(:otra) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Petición', codigo: 'peticion') }
    let(:pedir) { hash_including(content: described_class::MENSAJE_PEDIR_DATOS) }

    before do
      allow(runner).to receive(:run).and_return(instance_double(Agents::RunResult, output: 'ok', context: {}))
      allow(client).to receive(:update_custom_attributes)
    end

    def correr
      job.perform(account_id: account.id, conversation_id: conversation.display_id, content: 'hola')
    end

    it 'pide cédula/dirección/ciudad y marca la solicitud cuando la garantía no las tiene' do
      create(:ticket, account: account, conversation_id: conversation.id, categoria: garantia)

      expect(client).to receive(:create_message).with(conversation.display_id, pedir)
      expect(client).to receive(:update_custom_attributes)
        .with(conversation.display_id, { described_class::ATRIBUTO_DATOS_SOLICITADOS => true })

      correr
    end

    it 'NO los pide si la ficha ya está completa' do
      ticket = create(:ticket, account: account, conversation_id: conversation.id, categoria: garantia)
      Helic3::Casos::RegistrarDatos.new(ticket: ticket, fuente: :confirmado,
                                        campos: { cedula: '1', direccion: 'Calle 1', ciudad: 'Armenia' }).call

      expect(client).not_to receive(:create_message).with(conversation.display_id, pedir)

      correr
    end

    it 'NO los pide dos veces (ya se solicitaron)' do
      create(:ticket, account: account, conversation_id: conversation.id, categoria: garantia)
      conversation.update!(custom_attributes: { described_class::ATRIBUTO_DATOS_SOLICITADOS => true })

      expect(client).not_to receive(:create_message).with(conversation.display_id, pedir)

      correr
    end

    it 'NO los pide si el caso no es una garantía' do
      create(:ticket, account: account, conversation_id: conversation.id, categoria: otra)

      expect(client).not_to receive(:create_message).with(conversation.display_id, pedir)

      correr
    end

    # Flujo del mockup: cuando el cliente manda la FOTO de la factura, el OCR lee los datos
    # y el agente los PRESENTA para que confirme (ver PqrsAgent). El pedido determinista
    # duplicaría ese mensaje, así que en el turno de una foto legible NO se dispara.
    it 'NO los pide en el turno de una foto con texto legible (el agente presenta el OCR para confirmar)' do
      create(:ticket, account: account, conversation_id: conversation.id, categoria: garantia)
      allow(Helic3::Agents::LectorDeImagenes).to receive(:leer).and_return('cliente Ana Ruiz, cedula 123, ciudad Pereira')

      expect(client).not_to receive(:create_message).with(conversation.display_id, pedir)

      job.perform(account_id: account.id, conversation_id: conversation.display_id,
                  content: 'aquí está mi factura', imagenes: ['http://x/factura.jpg'])
    end

    # Red de seguridad intacta: si llegó una foto pero el OCR no leyó nada útil (foto borrosa,
    # del producto y no de un documento), el pedido determinista SÍ debe dispararse.
    it 'SÍ los pide si llegó una foto pero el OCR no leyó texto' do
      create(:ticket, account: account, conversation_id: conversation.id, categoria: garantia)
      allow(Helic3::Agents::LectorDeImagenes).to receive(:leer).and_return(nil)

      expect(client).to receive(:create_message).with(conversation.display_id, pedir)

      job.perform(account_id: account.id, conversation_id: conversation.display_id,
                  content: 'aquí está mi factura', imagenes: ['http://x/borrosa.jpg'])
    end
  end
end
