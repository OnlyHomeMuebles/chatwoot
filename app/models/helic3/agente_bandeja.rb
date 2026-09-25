# frozen_string_literal: true

# H3A-02: vinculo agente <-> inbox. Un agente atiende en varios inboxes y un
# inbox puede tener varios agentes (la orquesta), sin el bloqueo de "uno por
# bandeja" (esa regla del mockup se descarto en H3A-14).
# == Schema Information
#
# Table name: helic3_agentes_bandejas
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  agente_id  :bigint           not null
#  inbox_id   :bigint           not null
#
# Indexes
#
#  idx_h3agb_agente        (agente_id)
#  idx_h3agb_agente_inbox  (agente_id,inbox_id) UNIQUE
#  idx_h3agb_inbox         (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (agente_id => helic3_agentes.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
class Helic3::AgenteBandeja < ApplicationRecord
  # Rails derivaria 'helic3_agente_bandejas'; la tabla es 'helic3_agentes_bandejas'
  self.table_name = 'helic3_agentes_bandejas'

  belongs_to :agente, class_name: 'Helic3::Agente', inverse_of: :agente_bandejas
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :agente_id }

  # H3A-06: cambiar en que bandeja atiende un agente invalida la cache de config.
  # Si el agente ya se borro en cascada, su propio after_commit ya invalido.
  after_commit :invalidar_config_cache

  private

  def invalidar_config_cache
    Helic3::Agents::ConfigCache.invalidar(agente&.account_id)
  end
end
