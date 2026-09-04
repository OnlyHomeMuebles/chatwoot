json.id resource.id
json.display_id resource.display_id
json.ticket_number resource.ticket_number
json.title resource.title
json.description resource.description
json.status resource.status
json.conversation_id resource.conversation_id
json.resolved_at resource.resolved_at
json.created_at resource.created_at
json.updated_at resource.updated_at

# Clasificacion (API-02): cada llave como objeto id/codigo/nombre, o nulo cuando
# no esta asignada — un expediente sin clasificar no rompe la vista.
%i[categoria tipo motivo_pqr resultado etapa].each do |llave|
  registro = resource.public_send(llave)
  if registro
    json.set! llave do
      json.call(registro, :id, :codigo, :nombre)
    end
  else
    json.set! llave, nil
  end
end

# Reloj y radicado (API-02 + SEM-01): los sellos son columnas; el numero, los
# dias restantes, el semaforo y el congelamiento se derivan del modelo. Nulos
# cuando la categoria no genera radicado (p. ej. Informacion).
json.numero_radicado resource.numero_radicado
json.radicada_at resource.radicada_at
json.respondida_at resource.respondida_at
json.cerrada_at resource.cerrada_at
json.plazo_respuesta_vence_at resource.plazo_respuesta_vence_at
json.dias_habiles_restantes resource.dias_habiles_restantes
json.semaforo resource.semaforo
json.reloj_detenido resource.reloj_detenido?
json.origen resource.pqrs_metadata&.dig('origen')

if resource.assignee.present?
  json.assignee do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.assignee
  end
else
  json.assignee nil
end

if resource.creator.present?
  json.creator do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.creator
  end
else
  json.creator nil
end
