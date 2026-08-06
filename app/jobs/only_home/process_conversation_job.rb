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

  def perform(account_id:, conversation_id:, content:)
    configure_llm
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
    context = memory.load
    context[:state] = { conversation_id: conversation_id, chatwoot_client: client }

    result = OnlyHome::RunnerService.new(**llm_options).run(content, context: context)

    if result.output.to_s.strip.present?
      memory.save(result.context)
      result.output
    else
      Rails.logger.error("[OnlyHome] runner sin salida conv=#{conversation_id}: #{result.error&.message}")
      FALLBACK_REPLY
    end
  rescue StandardError => e
    Rails.logger.error("[OnlyHome] error procesando conv=#{conversation_id}: #{e.class}: #{e.message}")
    FALLBACK_REPLY
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

  def gemini?
    ENV['GEMINI_API_KEY'].to_s.strip.present?
  end

  # Gemini se consume por su endpoint compatible con OpenAI: el proveedor nativo :gemini rechaza el
  # rol 'function' que genera el handoff entre agentes; el endpoint OpenAI maneja bien las herramientas.
  def configure_llm
    if gemini?
      Agents.configure do |config|
        config.openai_api_key = ENV.fetch('GEMINI_API_KEY')
        config.openai_api_base = ENV.fetch('GEMINI_OPENAI_BASE', 'https://generativelanguage.googleapis.com/v1beta/openai')
      end
    else
      Agents.configure { |config| config.ollama_api_base = ENV.fetch('OLLAMA_API_BASE', 'http://localhost:11434/v1') }
    end
  end

  def llm_options
    if gemini?
      { model: ENV.fetch('GEMINI_MODEL', 'gemini-flash-latest'), provider: :openai, assume_model_exists: true }
    else
      { model: ENV.fetch('OLLAMA_MODEL', 'llama3.2'), provider: :ollama, assume_model_exists: true }
    end
  end
end
