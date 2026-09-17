# frozen_string_literal: true

# Reads the recent messages of the current Chatwoot conversation so the copilot has context
# before suggesting a reply. Read-only. API: GET /api/v1/accounts/:id/conversations/:id/messages
class OnlyHome::Tools::GetConversationTool < OnlyHome::Tools::BaseTool
  MAX_MESSAGES = 20

  description 'Lee los mensajes recientes de la conversación actual para tener contexto.'

  def perform(tool_context)
    with_api_error_handling do
      messages = client(tool_context).conversation_messages(conversation_id(tool_context))
      transcript = messages.filter_map { |message| format_line(message) }.last(MAX_MESSAGES)
      transcript.presence&.join("\n") || 'La conversación aún no tiene mensajes de texto.'
    end
  end

  private

  def format_line(message)
    content = message['content'] || message[:content]
    return if content.blank?

    incoming = (message['message_type'] || message[:message_type]).to_i.zero?
    "#{incoming ? 'Cliente' : 'Agente'}: #{content}"
  end
end
