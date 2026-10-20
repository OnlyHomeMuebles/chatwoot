# IND-03 (parcial): una fila por archivo subido en "Carga de Datos". Hoy solo
# el tipo 'facturas' tiene parser real -- 'garantias'/'peticiones'/
# 'devoluciones' (IND-04) esperan a que se sepan sus columnas en el Dash CX
# (documento de tickets IND, seccion 9: "solo se vio la de Facturas").
class CreateHelic3Cargas < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_cargas do |t|
      t.bigint :account_id, null: false
      t.string :tipo, null: false
      t.string :nombre_archivo, null: false
      t.string :modo, null: false
      t.bigint :usuario_id
      t.string :estado, null: false, default: 'procesando'
      t.integer :filas_leidas, null: false, default: 0
      t.integer :filas_insertadas, null: false, default: 0
      t.integer :filas_actualizadas, null: false, default: 0
      t.integer :filas_omitidas, null: false, default: 0
      t.jsonb :errores, null: false, default: []

      t.timestamps
    end

    add_index :helic3_cargas, :account_id, name: 'idx_h3_cargas_account'
    add_index :helic3_cargas, %i[account_id tipo], name: 'idx_h3_cargas_account_tipo'
    add_foreign_key :helic3_cargas, :users, column: :usuario_id
  end
end
