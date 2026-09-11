# Fila de la cola de decisiones (DEC-01). Referencia del expediente, que propuso
# el agente, desde cuando espera, el estado del reloj legal y la regla que la trajo.
json.id ticket.id
json.display_id ticket.display_id
json.numero_radicado ticket.numero_radicado
json.title ticket.title

json.cliente do
  json.nombre ticket.conversation&.contact&.name
end

# La propuesta del agente vive en pqrs_metadata; se resolvio a objeto en el
# controlador (precargado, sin N+1). aprobacion_humana es la regla que la trajo.
propuesta = propuestas[ticket.pqrs_metadata['resultado_propuesto_id']]
if propuesta
  json.propuesta do
    json.id propuesta.id
    json.codigo propuesta.codigo
    json.nombre propuesta.nombre
    json.aprobacion_humana propuesta.aprobacion_humana
  end
else
  json.propuesta nil
end

json.propuesto_at ticket.pqrs_metadata['propuesto_at']

# Estado del reloj legal, para ordenar/urgir en el cliente sin recalcular.
json.plazo_respuesta_vence_at ticket.plazo_respuesta_vence_at
json.dias_habiles_restantes ticket.dias_habiles_restantes
json.reloj_detenido ticket.reloj_detenido?
