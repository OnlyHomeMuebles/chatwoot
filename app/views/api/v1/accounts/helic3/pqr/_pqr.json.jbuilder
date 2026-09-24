# Fila de la bandeja de PQR (BAN-01). Trae las columnas del mockup, SIN semaforo
# ni dias_habiles_restantes: son derivados y costarian por fila. Se expone
# plazo_respuesta_vence_at para que el cliente pinte el color con los umbrales.
json.id ticket.id
json.display_id ticket.display_id
json.numero_radicado ticket.numero_radicado
json.title ticket.title
json.status ticket.status
json.conversation_display_id ticket.conversation&.display_id
json.origen ticket.pqrs_metadata&.dig('origen')

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

# Reloj legal: fecha de vencimiento, sellos y los dias habiles restantes (calculo
# en memoria, sin consulta). Con dias_habiles_restantes + los umbrales del meta el
# cliente pinta el color del semaforo sin duplicar la regla de dias habiles.
json.plazo_respuesta_vence_at ticket.plazo_respuesta_vence_at
json.respondida_at ticket.respondida_at
json.reloj_detenido ticket.reloj_detenido?
json.dias_habiles_restantes ticket.dias_habiles_restantes

# Cliente: nombre de la conversacion y documento de los datos del caso (DAT-01);
# si aun no se recolecto la cedula, va nulo y la fila lo muestra como pendiente.
json.cliente do
  json.nombre ticket.conversation&.contact&.name
  json.documento ticket.datos&.cedula
end

# Ciudad para la columna Motivo (VIS-02): del dato del caso.
json.ciudad ticket.datos&.ciudad

# Escalamiento (VIS-02): nivel sobre la MISMA PQR (p. ej. derecho de peticion),
# guardado en pqrs_metadata. Nulo mientras no exista; no se inventa un valor.
json.escalamiento ticket.pqrs_metadata&.dig('escalamiento')

# Garantia (GAR-02): el radicado que cuelga del expediente y su proceso vigente,
# o nulo si la PQR no abrio garantia. El presupuesto NO va aqui (calcula dias
# habiles y festivos): la columna solo muestra numero y proceso.
if ticket.garantia
  json.garantia do
    json.numero_radicado ticket.garantia.numero_radicado
    proceso = ticket.garantia.proceso_visible
    json.proceso proceso&.nombre
  end
else
  json.garantia nil
end

# Responsable: solo id, nombre y avatar. NO se reusa el parcial _agent, que lee
# availability_status, role y avatar_url (account_users + ActiveStorage por fila).
if ticket.assignee
  json.assignee do
    json.id ticket.assignee.id
    json.name ticket.assignee.name
    json.thumbnail ticket.assignee.avatar_url
  end
else
  json.assignee nil
end
