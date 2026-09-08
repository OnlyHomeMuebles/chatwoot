# Fila de la bandeja de PQR (BAN-01). Trae las columnas del mockup, SIN semaforo
# ni dias_habiles_restantes: son derivados y costarian por fila. Se expone
# plazo_respuesta_vence_at para que el cliente pinte el color con los umbrales.
json.id ticket.id
json.display_id ticket.display_id
json.numero_radicado ticket.numero_radicado
json.title ticket.title
json.status ticket.status

# Clasificacion: cada llave como objeto id/codigo/nombre, o nulo. Un expediente
# sin clasificar no rompe la fila: los campos van vacios, no un error.
%i[categoria tipo motivo_pqr etapa].each do |llave|
  registro = ticket.public_send(llave)
  if registro
    json.set! llave do
      json.id registro.id
      json.codigo registro.codigo
      json.nombre registro.nombre
    end
  else
    json.set! llave, nil
  end
end

# Reloj legal: la fecha de vencimiento y los sellos que el cliente necesita para
# derivar el semaforo y el estado "vencido"/"congelado" sin recalcular en servidor.
json.plazo_respuesta_vence_at ticket.plazo_respuesta_vence_at
json.respondida_at ticket.respondida_at
json.reloj_detenido ticket.reloj_detenido?

# Cliente: hoy sale de la conversacion. La cedula/documento llega con datos
# (DAT-01, de Samuel); hasta entonces va nula, la fila la muestra como pendiente.
json.cliente do
  json.nombre ticket.conversation&.contact&.name
  json.documento nil
end

if ticket.assignee
  json.assignee do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: ticket.assignee
  end
else
  json.assignee nil
end
