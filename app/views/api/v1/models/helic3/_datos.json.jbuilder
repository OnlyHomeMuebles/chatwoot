# DAT-01: la ficha del caso con la procedencia por campo. Cada campo sale como
# { valor, fuente } o null cuando no hay dato, para que el panel pinte el badge
# sin una segunda consulta. `resource` es el Helic3::TicketDato o nil.
fuentes = resource&.fuentes || {}

%i[cedula direccion ciudad factura_numero producto_nombre
   cliente_nombre cliente_telefono cliente_email producto_referencia factura_fecha].each do |campo|
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

# ERP-15 (B3): los productos de la compra (uno o varios), cada uno con su procedencia. El
# panel los usa para precargar el dialogo de garantia con una fila por producto.
json.productos(resource&.productos || [])

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
