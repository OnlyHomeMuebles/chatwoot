# H3A-01: los agentes del bot dejan de vivir quemados en el codigo (nombre, prompt
# y herramientas en la clase) y pasan a ser datos administrables desde Chatwoot.
# Un cambio de tono o un agente nuevo es una fila, no un commit + deploy.
#
# Dos tablas: helic3_agentes (un registro por agente) y helic3_agentes_bandejas
# (que agente atiende en que inbox; varios inboxes por agente y viceversa).
#
# Notas de diseno pendientes de confirmar con Jhan (decisiones del ticket):
# - `modelo` queda por agente (como lista el ticket). Si se decide "modelo por
#   cuenta", esta columna simplemente queda nula y el modelo sale de LlmRuntime.
# - horario/confianza_minima/max_respuestas/team_id/mensaje_handoff son de nivel
#   "persona/conversacion". Viven por agente segun el ticket; falta definir la
#   precedencia cuando una conversacion pasa por varios agentes (triage -> pqrs).
#
# Indices con nombre corto explicito (idx_h3ag_*): los generados por Rails
# superarian el limite de 63 caracteres de Postgres.
class CreateHelic3Agentes < ActiveRecord::Migration[7.2]
  def change
    crear_tabla_agentes
    crear_tabla_bandejas
  end

  private

  # rubocop:disable Metrics/MethodLength -- una tabla con sus ~20 columnas es larga por naturaleza
  def crear_tabla_agentes
    create_table :helic3_agentes do |t|
      t.references :account, null: false,
                             index: { name: 'idx_h3ag_account' },
                             foreign_key: { to_table: :accounts, on_delete: :cascade }

      # identidad
      t.string :codigo, null: false          # nombre interno para los handoffs (agente_faq)
      t.string :nombre, null: false           # etiqueta visible en la UI
      t.text   :descripcion                    # que atiende, para el operador

      # comportamiento
      t.text   :criterio_ruteo                 # con que el triage decide enrutar aqui
      t.text   :prompt                          # instrucciones del agente (parte editable)
      t.string :tono
      t.string :modelo                          # override; nulo = default de LlmRuntime
      t.string :horario                         # 'siempre' | 'horario_atencion'

      # capacidades y limites (jsonb: se leen contra el catalogo fijo del codigo)
      t.jsonb  :herramientas, null: false, default: []
      t.jsonb  :politicas, null: false, default: {}
      t.text   :politicas_texto
      t.jsonb  :handoff_reglas, null: false, default: {}
      t.integer :confianza_minima
      t.integer :max_respuestas

      # derivacion al humano
      t.references :team, null: true,
                          index: { name: 'idx_h3ag_team' },
                          foreign_key: { on_delete: :nullify }
      t.text :mensaje_handoff

      # estado y trazabilidad
      t.boolean :activo, null: false, default: true
      t.boolean :es_sistema, null: false, default: false   # el triage; no se puede eliminar
      t.references :creado_por, null: true,
                                index: { name: 'idx_h3ag_creado_por' },
                                foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    # codigo unico por cuenta (criterio 1); lookup por cuenta + estado (el runner
    # filtra los activos de la cuenta en cada mensaje)
    add_index :helic3_agentes, %i[account_id codigo], unique: true, name: 'idx_h3ag_account_codigo'
    add_index :helic3_agentes, %i[account_id activo], name: 'idx_h3ag_account_activo'
  end
  # rubocop:enable Metrics/MethodLength

  # que agente atiende en que inbox. Borrado en cascada por ambos lados: si se
  # borra el inbox o el agente, el vinculo se va con el.
  def crear_tabla_bandejas
    create_table :helic3_agentes_bandejas do |t|
      t.references :agente, null: false,
                            index: { name: 'idx_h3agb_agente' },
                            foreign_key: { to_table: :helic3_agentes, on_delete: :cascade }
      t.references :inbox, null: false,
                           index: { name: 'idx_h3agb_inbox' },
                           foreign_key: { to_table: :inboxes, on_delete: :cascade }
      t.timestamps
    end

    # un agente no se vincula dos veces al mismo inbox (criterio 2)
    add_index :helic3_agentes_bandejas, %i[agente_id inbox_id], unique: true, name: 'idx_h3agb_agente_inbox'
  end
end
