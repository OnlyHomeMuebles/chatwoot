# MAN-01: la ficha del caso (helic3_ticket_datos) guarda ahora al cliente y la
# compra, para una PQR radicada a mano (sin conversacion, y por tanto sin contacto
# de Chatwoot de donde sacar nombre/telefono). Sin esto, un formato de garantia de
# una PQR manual saldria con CLIENTE y TELEFONO vacios.
#
# `factura_fecha` se llama asi a proposito: es el nombre que Helic3::Formatos::
# DatosDelFormato ya esperaba para FECHA_COMPRA (reemplaza al "AGT-11" que nunca
# entro). Tabla lateral: helic3_tickets no recibe columnas nuevas.
class AgregaDatosClienteYCompraAFicha < ActiveRecord::Migration[7.2]
  def change
    change_table :helic3_ticket_datos, bulk: true do |t|
      t.string :cliente_nombre
      t.string :cliente_telefono
      t.string :cliente_email
      t.string :producto_referencia
      t.date   :factura_fecha
    end
  end
end
