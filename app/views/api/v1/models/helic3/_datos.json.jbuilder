# DAT-01: la ficha del caso con la procedencia por campo. Cada campo sale como
# { valor, fuente } o null cuando no hay dato, para que el panel pinte el badge
# sin una segunda consulta. `resource` es el Helic3::TicketDato o nil.
fuentes = resource&.fuentes || {}

%i[cedula direccion ciudad factura_numero producto_nombre].each do |campo|
  valor = resource&.public_send(campo)
  if valor.present?
    json.set! campo do
      json.valor valor
      json.fuente fuentes[campo.to_s]
    end
  else
    json.set! campo, nil
  end
end

# el detalle es catalogo: el valor va como objeto id/codigo/nombre para que el
# panel muestre el nombre sin otra consulta.
detalle = resource&.detalle_tipificado
if detalle
  json.detalle_tipificado do
    json.valor do
      json.call(detalle, :id, :codigo, :nombre)
    end
    json.fuente fuentes['detalle_tipificado_id']
  end
else
  json.detalle_tipificado nil
end
