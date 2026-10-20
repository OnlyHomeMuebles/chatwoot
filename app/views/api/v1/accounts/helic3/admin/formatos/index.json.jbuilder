json.array! @formatos do |formato|
  json.id formato.id
  json.codigo formato.codigo
  json.nombre formato.nombre
  json.activo formato.activo
  json.activa_id formato.plantillas.activa.first&.id
  json.versiones formato.plantillas.order(version: :desc) do |plantilla|
    json.id plantilla.id
    json.version plantilla.version
    json.estado plantilla.estado
    json.marcadores plantilla.marcadores
  end
end
