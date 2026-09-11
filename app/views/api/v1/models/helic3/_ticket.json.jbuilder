json.id resource.id
json.display_id resource.display_id
json.ticket_number resource.ticket_number
json.title resource.title
json.description resource.description
json.status resource.status
json.conversation_id resource.conversation_id
# El frontend habla en display_id (lo que Chatwoot expone como "id" de la
# conversacion). Se expone aparte para que la vista compare display con display y
# nunca manipule el id de base de datos. Nulo si el expediente no tiene conversacion.
json.conversation_display_id resource.conversation&.display_id
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

# Reloj y radicado (API-02 + SEM-01): los sellos son columnas; el numero y el
# congelamiento se derivan barato. Nulos cuando la categoria no genera radicado.
json.numero_radicado resource.numero_radicado
json.radicada_at resource.radicada_at
json.respondida_at resource.respondida_at
json.cerrada_at resource.cerrada_at
json.plazo_respuesta_vence_at resource.plazo_respuesta_vence_at
json.reloj_detenido resource.reloj_detenido?
json.origen resource.pqrs_metadata&.dig('origen')

# semaforo y dias_habiles_restantes SOLO en la vista detallada (show/create): en
# el listado costarian una lectura de umbrales + calculo de festivos por fila, y
# en una cuenta sin umbrales sembrados harian fallar TODO el indice con 500. El
# panel los lee del expediente puntual, no de la lista.
if local_assigns.fetch(:detallado, true)
  json.dias_habiles_restantes resource.dias_habiles_restantes
  json.semaforo resource.semaforo

  # Garantia (GAR-02): el radicado que cuelga del expediente, o nulo si no hay.
  # Solo en detallado: su presupuesto calcula dias habiles y festivos.
  if resource.garantia
    json.garantia do
      json.partial! 'api/v1/models/helic3/garantia', formats: [:json], resource: resource.garantia
    end
  else
    json.garantia nil
  end
end

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
