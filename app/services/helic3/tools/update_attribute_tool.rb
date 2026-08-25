# frozen_string_literal: true

# Sets a custom attribute on the Chatwoot conversation (e.g. order number, city).
# API: POST /api/v1/accounts/:account_id/conversations/:id/custom_attributes
class Helic3::Tools::UpdateAttributeTool < Helic3::Tools::BaseTool
  description 'Guarda un atributo personalizado en la conversación de Chatwoot.'
  param :key, type: 'string', desc: 'Nombre del atributo (ej. "numero_pedido", "ciudad")'
  param :value, type: 'string', desc: 'Valor del atributo'

  def perform(tool_context, key:, value:)
    with_api_error_handling do
      client(tool_context).update_custom_attributes(conversation_id(tool_context), { key => value })
      "Atributo '#{key}' guardado en la conversación."
    end
  end
end
