# frozen_string_literal: true

# FMT-02: tabla del catalogo de formatos. Mismo patron que los demas catalogos de
# clasificacion (cuenta, codigo, nombre, posicion, activo). Indices con nombre corto
# porque los autogenerados por Rails superan el limite de 63 chars de Postgres.
# La SIEMBRA de los 4 formatos la hace el seeder (Helic3::Catalogo::SeederService),
# igual que el resto de catalogos en esta rama (via rake catalogos:sembrar).
class CreateHelic3CatalogoFormatos < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_catalogo_formatos do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'idx_h3cat_formatos_account' }
      t.string  :nombre,   null: false
      t.string  :codigo,   null: false
      t.integer :posicion, null: false, default: 0
      t.boolean :activo,   null: false, default: true
      t.timestamps
    end

    add_index :helic3_catalogo_formatos, %i[account_id codigo], unique: true,
                                                                name: 'idx_h3cat_formatos_account_codigo'
  end
end
