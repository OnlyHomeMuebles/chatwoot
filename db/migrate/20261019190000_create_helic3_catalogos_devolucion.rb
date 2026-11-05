# IND-06: catalogo propio de Devoluciones. Mismo criterio de CAT-01 (una fila
# administrable, no una constante).
#
# Solo el MOTIVO es propio de Devolucion (el porque de fondo es distinto al
# de una garantia). El detalle tipificado (la falla fisica concreta) y el
# proceso (la etapa operativa) se verifico contra el historico real: son el
# mismo vocabulario que ya usa Garantia ("Golpes y rayones", "Ruta en
# fabrica", etc.) -- Devolucion reusa esos dos catalogos ya existentes
# (helic3_catalogo_detalles_tipificados / helic3_catalogo_procesos_garantia)
# en vez de duplicarlos; la separacion de conteos la da la tabla propia
# helic3_devoluciones, no un catalogo clonado. Cobertura de ciudad tampoco se
# duplica, por el mismo motivo.
class CreateHelic3CatalogosDevolucion < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_catalogo_motivos_devolucion do |t|
      t.references :account, null: false, index: { name: 'idx_h3cat_motivos_devolucion_account' }
      t.string :nombre, null: false
      t.string :codigo, null: false
      t.integer :posicion, null: false, default: 0
      t.boolean :activo, null: false, default: true

      t.timestamps
    end
    add_index :helic3_catalogo_motivos_devolucion, %i[account_id codigo], unique: true,
                                                                          name: 'idx_h3cat_motivos_devolucion_account_codigo'
  end
end
