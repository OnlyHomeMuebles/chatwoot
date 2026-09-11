# EVT-01: la bitacora del expediente. Cada transicion (radicacion, resultado
# propuesto, resultado aplicado, apertura de garantia, avance de proceso,
# respuesta al cliente) queda registrada con QUIEN la hizo, CUANDO y DESDE DONDE.
# Es lo que le da contenido a la tarjeta de actividad (VIS-03) y lo que permite
# sustentar ante la SIC por que se nego una garantia.
# Tabla propia del modulo; ninguna columna nueva en tablas upstream.
class CreateHelic3Eventos < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_eventos do |t|
      t.references :account, null: false, foreign_key: true,
                             index: { name: 'idx_h3_eventos_account' }
      t.references :ticket, null: false, foreign_key: { to_table: :helic3_tickets },
                            index: { name: 'idx_h3_eventos_ticket' }
      # opcional: solo los eventos de garantia la traen
      t.references :garantia, foreign_key: { to_table: :helic3_garantias },
                              index: { name: 'idx_h3_eventos_garantia' }
      # quien lo hizo (nulo cuando lo hace el agente, que no es un User)
      t.references :actor, foreign_key: { to_table: :users },
                           index: { name: 'idx_h3_eventos_actor' }

      t.string :tipo, null: false     # el tipo de transicion (lista cerrada en el modelo)
      t.string :origen, null: false   # humano | agente
      # lo minimo para reconstruir la transicion; SIN datos del ERP (esos son de Siesa)
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end
  end
end
