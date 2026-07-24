# frozen_string_literal: true

# Runs the Only Home multi-agent system for an incoming customer message and posts the agent's
# reply back into the Chatwoot conversation. Triggered by the incoming-message webhook; the run
# context is tied to the Chatwoot conversation (display_id) so tools act on the right conversation.
class OnlyHome::ProcessConversationJob < ApplicationJob
  queue_as :default

  def perform(account_id:, conversation_id:, content:)
    client = OnlyHome::ChatwootClient.new(account_id: account_id)
    result = OnlyHome::RunnerService.new.run(
      content,
      context: { state: { conversation_id: conversation_id, chatwoot_client: client } }
    )

    reply = result.output.to_s
    client.create_message(conversation_id, content: reply, message_type: 'outgoing') if reply.present?
  end
end
