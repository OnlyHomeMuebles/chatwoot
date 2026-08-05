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
    result = OnlyHome::RunnerService.new(**llm_options).run(
      content,
      context: { state: { conversation_id: conversation_id, chatwoot_client: client } }
    )

    reply = result.output.to_s
    client.create_message(conversation_id, content: reply, message_type: 'outgoing') if reply.present?
  end

  private

  def gemini?
    ENV['GEMINI_API_KEY'].to_s.strip.present?
  end

  def configure_llm
    if gemini?
      Agents.configure { |config| config.gemini_api_key = ENV.fetch('GEMINI_API_KEY') }
    else
      Agents.configure { |config| config.ollama_api_base = ENV.fetch('OLLAMA_API_BASE', 'http://localhost:11434/v1') }
    end
  end

  def llm_options
    if gemini?
      { model: 'gemini-2.0-flash', provider: :gemini, assume_model_exists: true }
    else
      { model: ENV.fetch('OLLAMA_MODEL', 'llama3.2'), provider: :ollama, assume_model_exists: true }
    end
  end
end
