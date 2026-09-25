json.array!(@conversaciones) do |conv|
  codigo = conv.custom_attributes['helic3_agente_activo']
  json.conversation_id conv.display_id
  json.contacto conv.contact&.name
  json.agente_codigo codigo
  json.agente_nombre @nombres_agentes[codigo] || codigo
  json.actualizado conv.updated_at
end
