# frozen_string_literal: true

# MIG-02: una fila por consecutivo dentro de una corrida de migración. Cumple tres
# papeles a la vez (ticket v2, pieza 2): el reporte (resultado + ajustes aplicados),
# la prueba de idempotencia (consecutivo único por corrida) y la lista para revertir
# (ticket_id/garantia_id creados; vacíos en una simulación).
# == Schema Information
#
# Table name: helic3_migracion_casos
#
#  id           :bigint           not null, primary key
#  ajustes      :jsonb            not null
#  consecutivo  :integer          not null
#  mensaje      :text
#  resultado    :string           not null
#  simulacion   :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  garantia_id  :bigint
#  migracion_id :bigint           not null
#  ticket_id    :bigint
#
# Indexes
#
#  idx_h3_migracion_casos_account    (account_id)
#  idx_h3_migracion_casos_garantia   (garantia_id)
#  idx_h3_migracion_casos_migracion  (migracion_id)
#  idx_h3_migracion_casos_ticket     (ticket_id)
#  idx_h3_migracion_casos_unico      (migracion_id,consecutivo) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (garantia_id => helic3_garantias.id) ON DELETE => nullify
#  fk_rails_...  (migracion_id => helic3_migraciones.id) ON DELETE => cascade
#  fk_rails_...  (ticket_id => helic3_tickets.id) ON DELETE => nullify
#
class Helic3::Migracion::Caso < ApplicationRecord
  # Rails derivaría 'helic3_casos'; la tabla es 'helic3_migracion_casos'.
  self.table_name = 'helic3_migracion_casos'

  RESULTADOS = %w[ok omitido fallido].freeze

  belongs_to :corrida, class_name: 'Helic3::Migracion::Corrida',
                       foreign_key: :migracion_id, inverse_of: :casos
  belongs_to :account
  belongs_to :ticket, class_name: 'Helic3::Ticket', optional: true
  belongs_to :garantia, class_name: 'Helic3::Garantia', optional: true

  validates :consecutivo, presence: true,
                          uniqueness: { scope: :migracion_id }
  validates :resultado, inclusion: { in: RESULTADOS }

  scope :creados, -> { where(resultado: 'ok') }
end
