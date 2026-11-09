# frozen_string_literal: true

# ERP-14: cache por cuenta+cedula del resultado del ERP (cliente + compras). Guarda los
# objetos de valor del contrato serializados a jsonb, NO el payload crudo de Siesa. Una
# sola fila por cuenta+cedula; la vigencia la decide erp_cache_horas al leer. Indices con
# nombre corto (el autogenerado supera el limite de 63 chars de Postgres).
class CreateHelic3ErpConsultas < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_erp_consultas do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'idx_h3_erp_consultas_account' }
      t.string   :cedula,        null: false
      t.jsonb    :cliente                                 # Customer serializado, o null si no existe
      t.jsonb    :compras,       null: false, default: [] # [Invoice] serializadas (con sus items)
      t.string   :estado,        null: false # guardar siempre escribe 'encontrado' o 'sin_cliente'
      t.datetime :consultado_at, null: false
      t.timestamps
    end

    add_index :helic3_erp_consultas, %i[account_id cedula], unique: true,
                                                            name: 'idx_h3_erp_consultas_cta_cedula'
  end
end
