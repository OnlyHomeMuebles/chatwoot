# frozen_string_literal: true

# FMT-02: versiones de plantilla por formato. Una plantilla es un .docx subido por
# Karen (adjunto :original) + su conversion a .fodt (adjunto :fodt, lo que se llena).
# Por formato hay varias versiones; solo UNA queda activa (indice parcial unico).
class CreateHelic3PlantillasFormato < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_plantillas_formato do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'idx_h3_plantilla_formato_account' }
      t.bigint   :formato_id, null: false
      t.integer  :version, null: false
      t.string   :estado, null: false, default: 'borrador'
      t.jsonb    :marcadores, null: false, default: []
      t.bigint   :subido_por_id
      t.string   :subido_por_nombre
      t.datetime :activada_at
      t.bigint   :activada_por_id
      t.timestamps

      t.index :formato_id, name: 'idx_h3_plantilla_formato_formato'
      t.index %i[formato_id version], unique: true, name: 'idx_h3_plantilla_formato_version'
    end

    agregar_activa_unica_y_fks
  end

  private

  def agregar_activa_unica_y_fks
    # indice PARCIAL: la unicidad solo aplica a las filas 'activa', asi que puede haber
    # muchas 'borrador'/'retirada' pero solo una 'activa' por formato.
    add_index :helic3_plantillas_formato, :formato_id, unique: true,
                                                       where: "estado = 'activa'", name: 'idx_h3_plantilla_activa_unica'

    add_foreign_key :helic3_plantillas_formato, :helic3_catalogo_formatos, column: :formato_id
    add_foreign_key :helic3_plantillas_formato, :users, column: :subido_por_id, on_delete: :nullify
    add_foreign_key :helic3_plantillas_formato, :users, column: :activada_por_id, on_delete: :nullify
  end
end
