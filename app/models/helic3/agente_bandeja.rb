# frozen_string_literal: true

# H3A-02: vinculo agente <-> inbox. Un agente atiende en varios inboxes y un
# inbox puede tener varios agentes (la orquesta), sin el bloqueo de "uno por
# bandeja" (esa regla del mockup se descarto en H3A-14).
class Helic3::AgenteBandeja < ApplicationRecord
  # Rails derivaria 'helic3_agente_bandejas'; la tabla es 'helic3_agentes_bandejas'
  self.table_name = 'helic3_agentes_bandejas'

  belongs_to :agente, class_name: 'Helic3::Agente', inverse_of: :agente_bandejas
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :agente_id }
end
