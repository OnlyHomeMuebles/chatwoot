# frozen_string_literal: true

# Runs the Only Home multi-agent system for an incoming customer message and posts the agent's
# reply back into the Chatwoot conversation. Triggered by the incoming-message webhook; the run
# context is tied to the Chatwoot conversation (display_id) so tools act on the right conversation.
#
# Elige el "cerebro" del agente: Gemini si hay GEMINI_API_KEY, si no un modelo local (Ollama),
# para poder responder sin depender de una API key de OpenAI.
class OnlyHome::ProcessConversationJob < ApplicationJob
  queue_as :default

  # Mensaje de respaldo cuando el cerebro del agente falla (cuota, timeout, error del proveedor),
  # para no dejar al cliente en silencio.
  FALLBACK_REPLY = 'Estoy teniendo un inconveniente técnico en este momento 🙏. ' \
                   'Por favor intenta de nuevo en unos minutos.'
  # El free tier del LLM limita por minuto (p. ej. "retry in 2s"); reintentamos con una espera corta
  # antes de rendirnos, para que ese límite pasajero sea transparente para el cliente.
  MAX_LLM_ATTEMPTS = 2
  MAX_RETRY_WAIT = 4

  def perform(account_id:, conversation_id:, content:)
    configure_llm
    @account_id = account_id
    client = OnlyHome::ChatwootClient.new(account_id: account_id)
    memory = OnlyHome::ConversationMemory.new(account_id: account_id, conversation_id: conversation_id)

    start_typing(client, conversation_id)
    reply = generate_reply(client, memory, conversation_id, content)
    client.create_message(conversation_id, content: reply, message_type: 'outgoing') if reply.present?
  ensure
    stop_typing(client, conversation_id)
  end

  private

  # Corre el multiagente restaurando el hilo previo. Ante un fallo del LLM devuelve un mensaje de
  # respaldo para que el cliente nunca quede sin respuesta, y no persiste un estado a medias.
  def generate_reply(client, memory, conversation_id, content)
    result = run_with_retries(client, memory, conversation_id, content)

    if result && result.output.to_s.strip.present?
      memory.save(result.context)
      result.output
    else
      Rails.logger.error("[OnlyHome] runner sin salida conv=#{conversation_id}: #{result&.error&.message}")
      FALLBACK_REPLY
    end
  rescue StandardError => e
    Rails.logger.error("[OnlyHome] error procesando conv=#{conversation_id}: #{e.class}: #{e.message}")
    FALLBACK_REPLY
  end

  # Reintenta ante errores de cuota/tasa (límite por minuto del free tier), reconstruyendo el
  # contexto desde la memoria en cada intento (no se persiste nada hasta que hay una salida válida).
  def run_with_retries(client, memory, conversation_id, content)
    result = nil
    MAX_LLM_ATTEMPTS.times do |attempt|
      context = memory.load
      context[:account_id] = @account_id
      context[:state] = { conversation_id: conversation_id, chatwoot_client: client }
      result = OnlyHome::RunnerService.new(**llm_options).run(content, context: context)
      return result if result.output.to_s.strip.present?

      delay = retry_delay(result.error)
      break if delay.nil? || attempt >= MAX_LLM_ATTEMPTS - 1

      Rails.logger.warn("[OnlyHome] limite de cuota/tasa del LLM conv=#{conversation_id}; reintento en #{delay}s")
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
    Rails.logger.warn("[OnlyHome] no se pudo activar el indicador de escritura conv=#{conversation_id}: #{e.message}")
  end

  def stop_typing(client, conversation_id)
    client&.toggle_typing(conversation_id, on: false)
  rescue StandardError
    nil
  end

  # Cerebro del agente. Se puede forzar con ONLY_HOME_LLM_PROVIDER=openai|gemini|groq|ollama. Si no,
  # usa la API disponible (Gemini > OpenAI > Groq) y, como último recurso, el modelo local (Ollama).
  def llm_provider
    explicit = ENV['ONLY_HOME_LLM_PROVIDER'].to_s.strip.downcase
    return explicit.to_sym if %w[ollama gemini groq openai].include?(explicit)
    return :gemini if ENV['GEMINI_API_KEY'].to_s.strip.present?
    return :openai if ENV['OPENAI_API_KEY'].to_s.strip.present?
    return :groq if ENV['GROQ_API_KEY'].to_s.strip.present?

    :ollama
  end

  def configure_llm
    case llm_provider
    when :groq
      Agents.configure do |config|
        config.openai_api_key = ENV.fetch('GROQ_API_KEY')
        config.openai_api_base = ENV.fetch('GROQ_API_BASE', 'https://api.groq.com/openai/v1')
      end
    when :gemini
      Agents.configure do |config|
        config.openai_api_key = ENV.fetch('GEMINI_API_KEY')
        config.openai_api_base = ENV.fetch('GEMINI_OPENAI_BASE', 'https://generativelanguage.googleapis.com/v1beta/openai')
      end
    when :openai
      Agents.configure { |config| config.openai_api_key = ENV.fetch('OPENAI_API_KEY') }
    else
      Agents.configure { |config| config.ollama_api_base = ENV.fetch('OLLAMA_API_BASE', 'http://localhost:11434/v1') }
    end
  end

  def llm_options
    case llm_provider
    when :groq
      { model: ENV.fetch('GROQ_MODEL', 'llama-3.3-70b-versatile'), provider: :openai, assume_model_exists: true }
    when :gemini
      { model: ENV.fetch('GEMINI_MODEL', 'gemini-flash-latest'), provider: :openai, assume_model_exists: true }
    when :openai
      { model: ENV.fetch('ONLY_HOME_OPENAI_MODEL', 'gpt-4.1-mini'), provider: :openai, assume_model_exists: true }
    else
      { model: ENV.fetch('OLLAMA_MODEL', 'qwen2.5:14b'), provider: :ollama, assume_model_exists: true }
    end
  end
end
