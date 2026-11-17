# frozen_string_literal: true

# GAR-08: la observacion obligatoria con que se cierra una garantia. Columnas en
# la tabla propia helic3_garantias (no una tabla aparte: es un dato 1:1 del cierre,
# como cerrada_at). El autor se referencia a users con on_delete: :nullify -> borrar
# el usuario en Chatwoot no borra la garantia; QUIEN cerro queda igual en el evento
# garantia_finalizada (Evento guarda el snapshot del nombre en su payload).
class AgregaObservacionCierreAHelic3Garantias < ActiveRecord::Migration[7.2]
  def change
    change_table :helic3_garantias, bulk: true do |t|
      t.text :observacion_cierre
      t.datetime :observacion_cierre_at
      t.references :observacion_cierre_por, foreign_key: { to_table: :users, on_delete: :nullify },
                                            index: { name: 'idx_h3_garantias_obs_cierre_por' }
    end
  end
end
