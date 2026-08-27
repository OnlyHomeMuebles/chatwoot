# CAT-02: cierre de los catalogos de clasificacion, con las definiciones que
# Only Home confirmo el 24/08 (addendum del 24 de agosto).
#
# Frente A: el detalle tipificado deja de exigir motivo de garantia. Son dos
# ejes independientes: el motivo sale de una regla de FECHA y el detalle de la
# DESCRIPCION del dano ("tela motosa" puede ocurrir a los 20 o a los 200
# dias). La FK se conserva pero admite null.
#
# Frente B: tabla de parametros de operacion (clave, valor, unidad, cuenta):
# el presupuesto global de la garantia y los demas valores de operacion que
# no pertenecen a ningun catalogo puntual.
#
# Frente C: columnas que faltaban para poder sembrar el diseno validado.
class CierraCatalogosClasificacion < ActiveRecord::Migration[7.2]
  def change
    # Frente A
    change_column_null :helic3_catalogo_detalles_tipificados, :motivo_garantia_id, true

    # Frente B
    create_table :helic3_catalogo_parametros do |t|
      t.references :account, null: false, index: { name: 'idx_h3cat_parametros_account' }
      t.string :clave, null: false
      t.string :valor, null: false
      t.string :unidad, null: false

      t.timestamps
    end
    add_index :helic3_catalogo_parametros, [:account_id, :clave], unique: true,
                                                                  name: 'idx_h3cat_parametros_account_clave'

    # Frente C
    change_table :helic3_catalogo_motivos_pqr, bulk: true do |t|
      # 'abre_garantia' pasa de booleano a enum de tres estados: "Error de
      # despacho o entrega incompleta" abre garantia SEGUN el analisis. La
      # tabla aun no tiene semilla, por eso el cambio de tipo es directo.
      t.remove :abre_garantia, type: :boolean
      t.integer :abre_garantia, null: false, default: 0
      # el retracto de compra tiene plazo legal propio (5 dias habiles)
      t.integer :plazo_dias_habiles
    end

    # negar una garantia o aprobar un retracto exige persona con autoridad;
    # sin la columna, esa regla volveria al codigo
    add_column :helic3_catalogo_resultados, :aprobacion_humana, :boolean, null: false, default: false
  end
end
