# frozen_string_literal: true

# Runs the Only Home multi-agent system for an incoming customer message and posts the agent's
# reply back into the Chatwoot conversation. Triggered by the incoming-message webhook; the run
# context is tied to the Chatwoot conversation (display_id) so tools act on the right conversation.
#
# Elige el "cerebro" del agente: Gemini si hay GEMINI_API_KEY, si no un modelo local (Ollama),
# para poder responder sin depender de una API key de OpenAI.
class OnlyHome::ProcessConversationJob < ApplicationJob
  queue_as :default

  def perform(account_id:, conversation_id:, content:)
    configure_llm
    client = OnlyHome::ChatwootClient.new(account_id: account_id)
    memory = OnlyHome::ConversationMemory.new(account_id: account_id, conversation_id: conversation_id)

    # Se restaura el hilo previo (si lo hay) y se inyecta el estado de ejecución (no serializable),
    # de modo que el agente continúe la conversación en vez de arrancar de cero en cada mensaje.
    context = memory.load
    context[:state] = { conversation_id: conversation_id, chatwoot_client: client }

    result = OnlyHome::RunnerService.new(**llm_options).run(content, context: context)
    memory.save(result.context)

    reply = result.output.to_s
    client.create_message(conversation_id, content: reply, message_type: 'outgoing') if reply.present?
  end

  private

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
