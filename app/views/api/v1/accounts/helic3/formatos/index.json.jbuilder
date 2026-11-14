# FMT-04: formatos con su plantilla activa (si la hay) + items de la garantia
# con su formato sugerido y los marcadores que les quedan vacios. El front cruza
# los marcadores de la plantilla con los vacios del item para mostrar faltantes.
# FMT-07: marcadores que el operador llena en el modal (con etiqueta y tipo de
# campo). El front cruza esto con los marcadores de cada plantilla para saber
# que campos pintar.
json.marcadores_editables Helic3::Formatos::Marcadores.editables

json.formatos @formatos do |formato|
  activa = formato.plantillas.detect { |plantilla| plantilla.estado == 'activa' }
  json.id formato.id
  json.codigo formato.codigo
  json.nombre formato.nombre
  json.activo formato.activo
  if activa
    json.plantilla_activa do
      json.id activa.id
      json.version activa.version
      json.marcadores activa.marcadores || []
    end
  else
    json.plantilla_activa nil
  end
end

json.items @items do |fila|
  item = fila[:item]
  json.id item.id
  json.producto_nombre item.producto_nombre
  json.proceso_codigo item.proceso&.codigo
  # el formato sugerido vive en el proceso del item (parte D); el modal lo marca.
  json.formato_sugerido_id item.proceso&.formato_sugerido_id
  json.marcadores_vacios fila[:vacios]
  # ultimos valores editables por codigo de formato (para prellenar el modal).
  json.ultimos_valores fila[:ultimos]
end
