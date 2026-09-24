# frozen_string_literal: true

# Runs the Only Home multi-agent system for an incoming customer message and posts the agent's
# reply back into the Chatwoot conversation. Triggered by the incoming-message webhook; the run
# context is tied to the Chatwoot conversation (display_id) so tools act on the right conversation.
#
# Elige el "cerebro" del agente: Gemini si hay GEMINI_API_KEY, si no un modelo local (Ollama),
# para poder responder sin depender de una API key de OpenAI.
class Helic3::ProcessConversationJob < ApplicationJob
  queue_as :default

  # Mensaje de respaldo cuando el cerebro del agente falla (cuota, timeout, error del proveedor),
  # para no dejar al cliente en silencio.
  FALLBACK_REPLY = 'Estoy teniendo un inconveniente técnico en este momento 🙏. ' \
                   'Por favor intenta de nuevo en unos minutos.'
  # Mensaje al cliente cuando se derivó a un humano pero el agente no dejó texto propio.
  HANDOFF_REPLY = 'Con gusto te comunico con un asesor de Only Home 💙. En un momento te atienden por aquí.'
  # El free tier del LLM limita por minuto (p. ej. "retry in 2s"); reintentamos con una espera corta
  # antes de rendirnos, para que ese límite pasajero sea transparente para el cliente.
  MAX_LLM_ATTEMPTS = 2
  MAX_RETRY_WAIT = 4

  def perform(account_id:, conversation_id:, content:)
    Helic3::Agents::LlmRuntime.configure_agents!
    @account_id = account_id
    @account = Account.find_by(id: account_id)
    @client = Helic3::ChatwootClient.new(account_id: account_id)
    @inbox = inbox_de(conversation_id)
    @runner_service = Helic3::Agents::RunnerService.new(
      account: @account, inbox: @inbox, **Helic3::Agents::LlmRuntime.agents_options
    )
    # H3A-12 (crit 2): el modo (bd | clases) queda en el log de cada ejecucion.
    Rails.logger.info("[Helic3] conv=#{conversation_id} runner_modo=#{@runner_service.modo}")
    # H3A-08 (crit 3): sin agentes activos para la bandeja, se deja al humano.
    return dejar_al_humano(conversation_id) unless @runner_service.hay_agentes?
    # H3A-15 crit 2 / B4: si la conversacion ya no esta en territorio del bot (un humano
    # intervino -> 'open'), la IA no responde. Se mira el ESTADO, no una bandera que nunca
    # se limpia: asi, si el caso se resuelve y el cliente reabre (vuelve a 'pending'), responde.
    return dejar_por_intervencion(conversation_id) unless en_territorio_del_bot?(conversation_id)

    # H3A-11: limites del agente activo (horario / max_respuestas) antes de responder.
    decision = evaluar_limites(conversation_id)
    return aplicar_limite(conversation_id, decision) unless decision.accion == :responder

    atender(conversation_id, content)
  ensure
    stop_typing(@client, conversation_id) if @client
  end

  private

  # H3A-11: evalua los limites del agente activo (el que retomo el hilo, o el triage
  # en el primer mensaje) contra el numero de respuestas previas de la IA (turn_count).
  def evaluar_limites(conversation_id)
    contexto = Helic3::Agents::ConversationMemory.new(account_id: @account_id, conversation_id: conversation_id).load
    @agente_limites = agente_activo(contexto[:current_agent])
    Helic3::Agents::LimitesService.new(
      agente: @agente_limites, inbox: @inbox, respuestas_previas: contexto[:turn_count]
    ).evaluar
  end

  # agente que retoma el hilo (por codigo) o, si es el primer mensaje, el de sistema (triage).
  def agente_activo(codigo)
    return nil if @inbox.nil?

    agentes = Helic3::Agente.activos_para(@inbox)
    (codigo.present? && agentes.find_by(codigo: codigo)) || agentes.find_by(es_sistema: true)
  end

  # H3A-11 crit 1/2/3: aplica el corte y registra el motivo.
  def aplicar_limite(conversation_id, decision)
    Rails.logger.info("[Helic3][limites] conv=#{conversation_id} #{decision.accion}: #{decision.motivo}")
    return unless decision.accion == :derivar_equipo

    derivar_al_equipo(conversation_id)
  end

  # crit 1: pasa la conversacion al equipo con su mensaje_handoff y team_id. El
  # historial ya vive en Chatwoot, asi que el equipo la retoma con contexto.
  def derivar_al_equipo(conversation_id)
    mensaje = @agente_limites&.mensaje_handoff.presence || HANDOFF_REPLY
    @client.create_message(conversation_id, content: mensaje, message_type: 'outgoing')
    team_id = @agente_limites&.team_id
    @client.assign(conversation_id, team_id: team_id) if team_id.present?
    # B1 (revisión de Jhan): sacar la conversación del territorio del bot, igual que
    # HumanHandoffTool. Sin esto sigue en 'pending', que es lo que atiende el webhook:
    # como el runner no corre, turn_count no cambia y cada mensaje siguiente del cliente
    # volvería a recibir el handoff sin fin. Se hace SIEMPRE, aunque no haya team_id.
    @client.update_status(conversation_id, 'open')
  rescue StandardError => e
    Rails.logger.warn("[Helic3][limites] no se pudo derivar al equipo conv=#{conversation_id}: #{e.message}")
  end

  # corre el multiagente y publica la respuesta. Solo se llega aqui si hay agentes.
  def atender(conversation_id, content)
    memory = Helic3::Agents::ConversationMemory.new(account_id: @account_id, conversation_id: conversation_id)
    # AGT-07: el estado de consentimiento se lee de la conversacion (no de la memoria del
    # modelo), para que el aviso no se repita entre corridas. El triage lo recibe en el state.
    @consentimiento_datos_at = consentimiento_de_datos(conversation_id)

    start_typing(@client, conversation_id)
    reply = generate_reply(@client, memory, conversation_id, content)
    @client.create_message(conversation_id, content: reply, message_type: 'outgoing') if reply.present?
    emitir_estado(conversation_id)
    encolar_radicacion(conversation_id)
  end

  def dejar_al_humano(conversation_id)
    Rails.logger.info("[Helic3] sin agentes activos para la bandeja de conv=#{conversation_id}; se deja al equipo humano")
  end

  # H3A-15 crit 2: la conversacion ya no esta en territorio del bot (un humano la tomo).
  def dejar_por_intervencion(conversation_id)
    Rails.logger.info("[Helic3] conv=#{conversation_id} fuera del territorio del bot (intervenida); la IA no responde")
  end

  # H3A-15 crit 2 / B4: territorio del bot = conversacion en 'pending'. Fuera de ahi
  # (open/resolved/snoozed) la atiende una persona y la IA no responde. Se mira el ESTADO
  # y no una bandera que nunca se limpia, para que al reabrirse en 'pending' la IA vuelva.
  # best-effort: ante un error de lectura, se asume territorio del bot (responde).
  def en_territorio_del_bot?(display_id)
    conv = conversacion(display_id)
    # si no se puede resolver la conversacion, best-effort: se asume territorio del bot
    # (responde), igual que antes. Solo se corta cuando SE SABE que ya no esta en 'pending'.
    conv.nil? || conv.status == 'pending'
  rescue StandardError
    true
  end

  # H3A-15 crit 1: publica en la conversacion que agente esta atendiendo. Escribir el
  # custom_attribute dispara conversation.updated (Chatwoot ya lo difunde), asi que la
  # vista en vivo se actualiza sin recargar. Best-effort: nunca rompe la respuesta.
  def emitir_estado(display_id)
    return if @codigo_agente_activo.blank?

    @client.update_custom_attributes(display_id, { helic3_agente_activo: @codigo_agente_activo })
  rescue StandardError => e
    Rails.logger.warn("[Helic3] no se pudo emitir el estado del agente conv=#{display_id}: #{e.message}")
  end

  # N5 (revision de Jhan): la conversacion se resuelve UNA sola vez por corrida y se
  # memoiza; antes se consultaba 2-3 veces (bandeja + consentimiento + cuenta).
  def conversacion(display_id)
    return @conversacion if defined?(@conversacion)

    @conversacion = @account&.conversations&.find_by(display_id: display_id)
  rescue StandardError => e
    Rails.logger.warn("[Helic3] no se pudo resolver la conversación conv=#{display_id}: #{e.message}")
    @conversacion = nil
  end

  # bandeja de la conversacion; el runner filtra los agentes activos por ella (H3A-08)
  def inbox_de(display_id)
    conversacion(display_id)&.inbox
  end

  # AGT-07: lee el sello de consentimiento del atributo de la conversacion (best-effort: si no
  # se puede leer, se asume sin consentimiento y el aviso se mostrara).
  def consentimiento_de_datos(display_id)
    conversacion(display_id)&.custom_attributes&.dig('helic3_consentimiento_datos_at')
  end

  # AGT-06: la radicacion determinista corre en su propio job (async), no aqui, para no
  # retrasar la respuesta ni el indicador de escritura. Se encola SIEMPRE: no se filtra por el
  # agente activo, porque una garantia puede vivir entera en FAQ/cotizacion si el triage no la
  # reenruta (paso no determinista) y entonces nunca se radicaria. El job es idempotente y barato
  # cuando no procede: expediente_existente? (consulta indexada) corta antes de llamar al LLM.
  def encolar_radicacion(display_id)
    Helic3::RadicarAutomaticoJob.perform_later(account_id: @account_id, conversation_id: display_id)
  end

  # Corre el multiagente restaurando el hilo previo. Ante un fallo del LLM devuelve un mensaje de
  # respaldo para que el cliente nunca quede sin respuesta, y no persiste un estado a medias.
  def generate_reply(client, memory, conversation_id, content)
    result = run_with_retries(client, memory, conversation_id, content)
    # H3A-15: agente que atendio esta corrida (para publicarlo como estado en vivo).
    @codigo_agente_activo = agente_del_resultado(result)

    if result && result.output.to_s.strip.present?
      memory.save(result.context)
      result.output
    elsif escalated?(result)
      HANDOFF_REPLY
    else
      Rails.logger.error("[Helic3] runner sin salida conv=#{conversation_id}: #{result&.error&.message}")
      FALLBACK_REPLY
    end
  rescue StandardError => e
    Rails.logger.error("[Helic3] error procesando conv=#{conversation_id}: #{e.class}: #{e.message}")
    FALLBACK_REPLY
  end

  # H3A-15: codigo del agente que atendio (current_agent del contexto del resultado).
  def agente_del_resultado(result)
    result&.context.is_a?(Hash) ? result.context[:current_agent] : nil
  end

  # ¿El agente derivó la conversación a un humano durante el run? (lo marca HumanHandoffTool).
  def escalated?(result)
    ctx = result&.context
    ctx.respond_to?(:dig) && ctx.dig(:state, :escalated).present?
  end

  # Reintenta ante errores de cuota/tasa (límite por minuto del free tier), reconstruyendo el
  # contexto desde la memoria en cada intento (no se persiste nada hasta que hay una salida válida).
  def run_with_retries(client, memory, conversation_id, content)
    result = nil
    MAX_LLM_ATTEMPTS.times do |attempt|
      context = memory.load
      context[:account_id] = @account_id
      context[:state] = { conversation_id: conversation_id, chatwoot_client: client,
                          consentimiento_datos_at: @consentimiento_datos_at }
      result = @runner_service.run(content, context: context)
      return result if result.output.to_s.strip.present?

      delay = retry_delay(result.error)
      break if delay.nil? || attempt >= MAX_LLM_ATTEMPTS - 1

      Rails.logger.warn("[Helic3] limite de cuota/tasa del LLM conv=#{conversation_id}; reintento en #{delay}s")
      sleep(delay)
    end
    result
  end

  # Segundos a esperar si el error es de cuota/tasa (acotado a MAX_RETRY_WAIT), o nil si no procede reintentar.
  def retry_delay(error)
    msg = error&.message.to_s
    return nil unless msg.match?(/quota|rate.?limit|exceeded|429|RESOURCE_EXHAUSTED/i)

    suggested = msg[/retry in ([\d.]+)s/i, 1]&.to_f
    (suggested || 2).clamp(1, MAX_RETRY_WAIT)
  end

  # UX de agente: muestra el indicador de "escribiendo…" mientras se genera la respuesta. Es
  # best-effort: si el indicador falla, no debe impedir que se responda.
  def start_typing(client, conversation_id)
    client.toggle_typing(conversation_id, on: true)
    @typing_on = true
  rescue StandardError => e
    Rails.logger.warn("[Helic3] no se pudo activar el indicador de escritura conv=#{conversation_id}: #{e.message}")
  end

  # N5 (revision de Jhan): solo se apaga si se llego a encender. En el camino sin
  # agentes (dejar_al_humano) nunca hubo start_typing, asi que se evita una llamada
  # de mas a la API por cada conversacion sin agentes.
  def stop_typing(client, conversation_id)
    return unless @typing_on

    client&.toggle_typing(conversation_id, on: false)
    @typing_on = false
  rescue StandardError
    nil
  end
end
