# Serializacion explicita, guiada por la whitelist @campos del controlador (no
# json.merge! attributes): el contrato no se acopla al esquema ni vuelca columnas
# internas como account_id o timestamps.
json.id registro.id
@campos.each do |campo|
  json.set! campo, registro.public_send(campo)
end
