# frozen_string_literal: true

# MIG-02: las dos tablas de la pantalla de migración de garantías en Super Admin.
# - helic3_migraciones: una fila por corrida (un vaciado o una migración), con su
#   estado, totales, quién la subió/confirmó y el archivo subido (ActiveStorage).
# - helic3_migracion_casos: una fila por consecutivo dentro de una corrida. Es a la
#   vez el reporte, la prueba de idempotencia (consecutivo único por corrida) y la
#   lista para revertir (guarda ticket_id/garantia_id creados; vacíos en simulación).
class CreateHelic3Migraciones < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_migraciones do |t|
      t.references :account, null: false, foreign_key: true,
                             index: { name: 'idx_h3_migraciones_account' }
      t.string :tipo, null: false                        # vaciado | migracion
      t.string :estado, null: false, default: 'pendiente'
      t.string :archivo_nombre
      t.integer :total_leidos, null: false, default: 0
      t.integer :total_ok, null: false, default: 0
      t.integer :total_omitidos, null: false, default: 0
      t.integer :total_fallidos, null: false, default: 0
      # quién subió el archivo y quién confirmó (CA: queda registro). nullify para no
      # perder la corrida si el usuario se borra en Chatwoot.
      t.references :subido_por, foreign_key: { to_table: :users, on_delete: :nullify },
                                index: { name: 'idx_h3_migraciones_subido_por' }
      t.references :confirmado_por, foreign_key: { to_table: :users, on_delete: :nullify },
                                    index: { name: 'idx_h3_migraciones_confirmado_por' }
      t.datetime :iniciado_at
      t.datetime :finalizado_at
      # desglose del vaciado: cuántos registros borró de cada tabla (CA de la sección 5).
      t.jsonb :conteos, null: false, default: {}

      t.timestamps
    end

    create_table :helic3_migracion_casos do |t|
      t.references :migracion, null: false,
                               foreign_key: { to_table: :helic3_migraciones, on_delete: :cascade },
                               index: { name: 'idx_h3_migracion_casos_migracion' }
      t.references :account, null: false, foreign_key: true,
                             index: { name: 'idx_h3_migracion_casos_account' }
      t.integer :consecutivo, null: false
      # el PQR y la garantía creados por este caso; vacíos en simulación. nullify para
      # que revertir/vaciar (que borran el ticket) no choque con esta fila histórica.
      t.references :ticket, foreign_key: { to_table: :helic3_tickets, on_delete: :nullify },
                            index: { name: 'idx_h3_migracion_casos_ticket' }
      t.references :garantia, foreign_key: { to_table: :helic3_garantias, on_delete: :nullify },
                              index: { name: 'idx_h3_migracion_casos_garantia' }
      t.string :resultado, null: false                   # ok | omitido | fallido
      t.text :mensaje
      # las reglas de limpieza de MIG-01 que se aplicaron a este consecutivo (CA: el
      # reporte de la simulación lista los ajustes por caso).
      t.jsonb :ajustes, null: false, default: []
      t.boolean :simulacion, null: false, default: false

      t.timestamps
    end
    # idempotencia a nivel de datos: un consecutivo no se repite dentro de una corrida.
    add_index :helic3_migracion_casos, %i[migracion_id consecutivo], unique: true,
              name: 'idx_h3_migracion_casos_unico'
  end
end
