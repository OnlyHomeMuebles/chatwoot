# EXP-01: el expediente aprende el vocabulario de CAT-01/CAT-02 (cinco llaves
# opcionales: nace sin clasificar y el agente lo clasifica despues) y recibe
# los sellos del reloj legal. plazo_respuesta_vence_at solo se crea aqui:
# quien la calcula es PLZ-01, cuando se cablee.
# Solo toca helic3_tickets (tabla propia); ninguna tabla upstream de Chatwoot.
class AgregaClasificacionYRelojesAHelic3Tickets < ActiveRecord::Migration[7.2]
  def change
    change_table :helic3_tickets, bulk: true do |t|
      # clasificacion (nombres de indice cortos: Postgres corta en 63 chars)
      t.references :categoria, foreign_key: { to_table: :helic3_catalogo_categorias },
                               index: { name: 'idx_h3_tickets_categoria' }
      t.references :tipo, foreign_key: { to_table: :helic3_catalogo_tipos },
                          index: { name: 'idx_h3_tickets_tipo' }
      t.references :motivo_pqr, foreign_key: { to_table: :helic3_catalogo_motivos_pqr },
                                index: { name: 'idx_h3_tickets_motivo_pqr' }
      t.references :resultado, foreign_key: { to_table: :helic3_catalogo_resultados },
                               index: { name: 'idx_h3_tickets_resultado' }
      t.references :etapa, foreign_key: { to_table: :helic3_catalogo_etapas_pqr },
                           index: { name: 'idx_h3_tickets_etapa' }

      # sellos del reloj
      t.datetime :radicada_at
      t.datetime :respondida_at
      t.datetime :cerrada_at
      t.datetime :plazo_respuesta_vence_at
    end
  end
end
