# IND-03: las facturas de Siesa que alimentan Nº facturas/ratio/subtotal en
# Garantias. numero_documento es unico por cuenta (es la llave del modo
# "Sobrescribir / Actualizar" del Dash CX).
class CreateHelic3FacturasVenta < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_facturas_venta do |t|
      t.bigint :account_id, null: false
      t.string :numero_documento, null: false
      t.string :centro_operacion
      t.date :fecha, null: false
      t.decimal :valor_subtotal, precision: 14, scale: 2, null: false
      t.bigint :carga_id, null: false

      t.timestamps
    end

    add_index :helic3_facturas_venta, %i[account_id numero_documento], unique: true,
                                                                       name: 'idx_h3_facturas_account_numero'
    add_index :helic3_facturas_venta, :account_id, name: 'idx_h3_facturas_account'
    add_index :helic3_facturas_venta, :carga_id, name: 'idx_h3_facturas_carga'
    add_foreign_key :helic3_facturas_venta, :helic3_cargas, column: :carga_id
  end
end
