# H3A-05: serializacion del agente para el panel. Las bandejas van anidadas
# (criterio de aceptacion) para que la UI muestre en que inbox atiende cada agente.
json.id agente.id
json.codigo agente.codigo
json.nombre agente.nombre
json.descripcion agente.descripcion
json.criterio_ruteo agente.criterio_ruteo
json.prompt agente.prompt
json.tono agente.tono
json.modelo agente.modelo
json.horario agente.horario
json.herramientas agente.herramientas
json.confianza_minima agente.confianza_minima
json.max_respuestas agente.max_respuestas
json.team_id agente.team_id
json.mensaje_handoff agente.mensaje_handoff
json.politicas_texto agente.politicas_texto
json.activo agente.activo
json.es_sistema agente.es_sistema
json.created_at agente.created_at
json.updated_at agente.updated_at

json.bandejas agente.agente_bandejas do |bandeja|
  json.id bandeja.id
  json.inbox_id bandeja.inbox_id
  json.inbox_nombre bandeja.inbox&.name
end
