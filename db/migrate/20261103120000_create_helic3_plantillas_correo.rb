# frozen_string_literal: true

# COR-01: una plantilla de correo por proceso de garantia, mas una de cierre de
# caso (disparador = 'cierre_caso', sin proceso). Karen las edita desde
# Catalogos (COR-04); el texto nunca vive en Ruby, vistas ni i18n.
class CreateHelic3PlantillasCorreo < ActiveRecord::Migration[7.2]
  DISPARADORES = %w[proceso_garantia cierre_caso].freeze

  def change
    create_table :helic3_plantillas_correo do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'idx_h3_plantilla_correo_account' }
      t.bigint  :proceso_garantia_id
      t.string  :disparador, null: false
      t.string  :asunto, null: false
      t.text    :cuerpo, null: false
      t.boolean :activo, null: false, default: true
      t.timestamps
    end

    agregar_indices_fk_y_check
  end

  private

  def agregar_indices_fk_y_check
    add_foreign_key :helic3_plantillas_correo, :helic3_catalogo_procesos_garantia, column: :proceso_garantia_id

    # indices PARCIALES: una plantilla por proceso, y una sola de cierre de
    # caso (cierre_caso no lleva proceso, asi que no puede ir en el mismo
    # indice que proceso_garantia).
    add_index :helic3_plantillas_correo, %i[account_id proceso_garantia_id], unique: true,
                                                                             where: "disparador = 'proceso_garantia'",
                                                                             name: 'idx_h3_plantilla_correo_proceso_unico'
    add_index :helic3_plantillas_correo, :account_id, unique: true,
                                                      where: "disparador = 'cierre_caso'",
                                                      name: 'idx_h3_plantilla_correo_cierre_unico'

    add_check_constraint :helic3_plantillas_correo,
                         "(disparador = 'proceso_garantia' AND proceso_garantia_id IS NOT NULL) OR " \
                         "(disparador = 'cierre_caso' AND proceso_garantia_id IS NULL)",
                         name: 'check_h3_plantilla_correo_disparador'
  end
end
