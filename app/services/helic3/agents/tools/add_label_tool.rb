# frozen_string_literal: true

# Adds a label to the Chatwoot conversation, preserving any existing labels.
# API: GET + POST /api/v1/accounts/:account_id/conversations/:id/labels
class Helic3::Agents::Tools::AddLabelTool < Helic3::Agents::Tools::BaseTool
  description 'Agrega una etiqueta a la conversación en Chatwoot (conserva las etiquetas existentes).'
  param :label, type: 'string', desc: 'La etiqueta a agregar (ej. "pqrs", "cotizacion")'

  def perform(tool_context, label:)
    with_api_error_handling do
      client(tool_context).add_labels(conversation_id(tool_context), label)
      "Etiqueta '#{label}' agregada a la conversación."
    end
  end
end
