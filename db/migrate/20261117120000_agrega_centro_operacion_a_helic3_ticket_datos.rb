# frozen_string_literal: true

# ERP-18: la ficha guarda el centro de operacion de la factura. En ERP-18a el
# nombre se escribe a mano (centro_operacion_nombre); en ERP-18b el id lo trae la
# factura (compania + f350_id_co) y la ciudad se resuelve del catalogo contra el
# nombre del C.O. Las tres columnas se crean ya para no migrar dos veces. Tabla
# lateral a proposito: helic3_tickets no recibe columnas nuevas.
class AgregaCentroOperacionAHelic3TicketDatos < ActiveRecord::Migration[7.2]
  def change
    change_table :helic3_ticket_datos, bulk: true do |t|
      t.string :centro_operacion_id
      t.string :centro_operacion_nombre
      t.string :centro_operacion_ciudad
    end
  end
end
