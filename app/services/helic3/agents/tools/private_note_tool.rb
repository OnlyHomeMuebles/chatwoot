# frozen_string_literal: true

# Adds an internal private note (not visible to the customer) to the Chatwoot conversation.
# API: POST /api/v1/accounts/:account_id/conversations/:id/messages (private: true)
class Helic3::Agents::Tools::PrivateNoteTool < Helic3::Agents::Tools::BaseTool
  description 'Deja una nota privada interna en la conversación (no la ve el cliente).'
  param :note, type: 'string', desc: 'El contenido de la nota privada para el equipo'

  def perform(tool_context, note:)
    with_api_error_handling do
      client(tool_context).create_message(conversation_id(tool_context), content: note, private_note: true)
      'Nota privada agregada.'
    end
  end
end
