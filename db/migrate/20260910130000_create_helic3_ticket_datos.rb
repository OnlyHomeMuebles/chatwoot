# DAT-01: la ficha del caso. Tabla LATERAL 1:1 con el expediente (no se agrega
# ninguna columna a helic3_tickets): los datos recolectados del caso —cedula,
# direccion, ciudad, factura, producto, detalle tipificado— y de donde salio
# cada uno. La procedencia por campo vive en el jsonb `fuentes` (ia/erp/humano),
# que es lo que permite el badge del panel sin una segunda consulta.
# Solo crea una tabla propia del modulo; nada upstream de Chatwoot.
class CreateHelic3TicketDatos < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_ticket_datos do |t|
      # 1:1 con el expediente: indice unico sobre ticket_id
      t.references :ticket, null: false,
                            foreign_key: { to_table: :helic3_tickets },
                            index: { name: 'idx_h3_ticket_datos_ticket', unique: true }
      t.references :account, null: false, foreign_key: true,
                             index: { name: 'idx_h3_ticket_datos_account' }

      t.string :cedula
      t.string :direccion
      t.string :ciudad
      t.string :factura_numero
      t.string :producto_nombre
      t.references :detalle_tipificado,
                   foreign_key: { to_table: :helic3_catalogo_detalles_tipificados },
                   index: { name: 'idx_h3_ticket_datos_detalle' }

      # procedencia por campo: { "direccion" => "humano", "producto_nombre" => "ia" }
      t.jsonb :fuentes, null: false, default: {}

      t.timestamps
    end
  end
end
