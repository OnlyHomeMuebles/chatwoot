# frozen_string_literal: true

# Publishes the agent's reply as a public outgoing message in the Chatwoot conversation.
# API: POST /api/v1/accounts/:account_id/conversations/:id/messages (message_type: outgoing)
class OnlyHome::Tools::RespondTool < OnlyHome::Tools::BaseTool
  description 'Publica una respuesta pública para el cliente en la conversación de Chatwoot.'
  param :message, type: 'string', desc: 'El texto de la respuesta que verá el cliente'

  def perform(tool_context, message:)
    with_api_error_handling do
      client(tool_context).create_message(conversation_id(tool_context), content: message, message_type: 'outgoing')
      'Respuesta enviada al cliente.'
    end
  end
end
