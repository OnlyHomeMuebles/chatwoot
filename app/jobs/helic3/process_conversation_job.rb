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
    client = Helic3::ChatwootClient.new(account_id: account_id)
    memory = Helic3::Agents::ConversationMemory.new(account_id: account_id, conversation_id: conversation_id)

    start_typing(client, conversation_id)
    reply = generate_reply(client, memory, conversation_id, content)
    client.create_message(conversation_id, content: reply, message_type: 'outgoing') if reply.present?
    encolar_radicacion(conversation_id, memory)
  ensure
    stop_typing(client, conversation_id)
  end

  private

  # AGT-06: la radicacion determinista corre en su propio job (async), no aqui, para no
  # retrasar la respuesta ni el indicador de escritura. Solo se encola cuando el caso puede
  # necesitar expediente; el job es idempotente y decide si de verdad radica.
  def encolar_radicacion(display_id, memory)
    return unless compuerta_aplica?(memory)

    Helic3::RadicarAutomaticoJob.perform_later(account_id: @account_id, conversation_id: display_id)
  end

  # La compuerta corre cuando el caso puede necesitar expediente: con el agente de PQRS,
  # con el triage, o en los primeros turnos (current_agent aun vacio) — que es justo cuando
  # se radica. Solo se salta cuando el caso ya esta firmemente en FAQ/cotizacion/logistica,
  # para no gastar una clasificacion LLM ahi. El corte de costo real lo da expediente_existente?
  # (consulta indexada) antes de llamar al LLM, no este filtro.
  def compuerta_aplica?(memory)
    agente = memory.load[:current_agent].to_s.downcase
    agente.blank? || agente.include?('pqrs') || agente.include?('triage')
  end

  # Corre el multiagente restaurando el hilo previo. Ante un fallo del LLM devuelve un mensaje de
  # respaldo para que el cliente nunca quede sin respuesta, y no persiste un estado a medias.
  def generate_reply(client, memory, conversation_id, content)
    result = run_with_retries(client, memory, conversation_id, content)

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
      context[:state] = { conversation_id: conversation_id, chatwoot_client: client }
      result = Helic3::Agents::RunnerService.new(**Helic3::Agents::LlmRuntime.agents_options).run(content, context: context)
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
  rescue StandardError => e
    Rails.logger.warn("[Helic3] no se pudo activar el indicador de escritura conv=#{conversation_id}: #{e.message}")
  end

  def stop_typing(client, conversation_id)
    client&.toggle_typing(conversation_id, on: false)
  rescue StandardError
    nil
  end
end
