# frozen_string_literal: true

# ERP-15 (B3): la ficha puede recolectar VARIOS productos de una factura (el selector
# permite elegir uno o mas). Van en un jsonb con su procedencia por item
# ([{ nombre:, referencia:, fuente: }]); los campos sueltos producto_nombre/referencia
# siguen guardando el principal (el primero) para lo que ya los usa. Al abrir la garantia,
# cada producto de la lista se vuelve un item.
class AddProductosToHelic3TicketDatos < ActiveRecord::Migration[7.2]
  def change
    add_column :helic3_ticket_datos, :productos, :jsonb, null: false, default: []
  end
end
