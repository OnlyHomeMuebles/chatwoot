# Parcial reutilizable (EVI-02): la Semana 3 lo reusa para exponer los
# formatos de garantia desde la garantia misma, sin duplicar esta forma.
json.id documento.id
json.clase documento.clase
json.origen documento.origen
json.titulo documento.titulo
json.remitente do
  json.nombre documento.remitente_nombre
  json.user_id documento.remitente_user_id
end
json.ocurrido_at documento.ocurrido_at
json.tipo_archivo documento.tipo_archivo
json.url documento.url
