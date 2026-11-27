# frozen_string_literal: true

# MIG-02: una corrida de la pantalla de migración — un vaciado o una migración de
# garantías. Guarda el historial y el estado de cada ejecución, con el archivo que
# se subió (DataGrid en CSV) via ActiveStorage. El namespace Helic3::Migracion lo
# comparten los modelos (Corrida, Caso) y los servicios (ImportarGarantias, VaciarCasos).
# == Schema Information
#
# Table name: helic3_migraciones
#
#  id                :bigint           not null, primary key
#  archivo_nombre    :string
#  conteos           :jsonb            not null
#  estado            :string           default("pendiente"), not null
#  finalizado_at     :datetime
#  iniciado_at       :datetime
#  tipo              :string           not null
#  total_fallidos    :integer          default(0), not null
#  total_leidos      :integer          default(0), not null
#  total_ok          :integer          default(0), not null
#  total_omitidos    :integer          default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  confirmado_por_id :bigint
#  subido_por_id     :bigint
#
# Indexes
#
#  idx_h3_migraciones_account         (account_id)
#  idx_h3_migraciones_confirmado_por  (confirmado_por_id)
#  idx_h3_migraciones_subido_por      (subido_por_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (confirmado_por_id => users.id) ON DELETE => nullify
#  fk_rails_...  (subido_por_id => users.id) ON DELETE => nullify
#
class Helic3::Migracion::Corrida < ApplicationRecord
  # Rails derivaría 'helic3_corridas'; la tabla es 'helic3_migraciones'.
  self.table_name = 'helic3_migraciones'

  TIPOS = %w[vaciado migracion].freeze
  ESTADOS = %w[pendiente simulando simulado confirmando completada fallida revertida descartada].freeze

  belongs_to :account
  belongs_to :subido_por, class_name: 'User', optional: true
  belongs_to :confirmado_por, class_name: 'User', optional: true

  has_many :casos, class_name: 'Helic3::Migracion::Caso', foreign_key: :migracion_id,
                   inverse_of: :corrida, dependent: :destroy

  # el archivo subido (CSV del DataGrid). Se purga al terminar/fallar/descartar (regla 8).
  has_one_attached :archivo

  validates :tipo, inclusion: { in: TIPOS }
  validates :estado, inclusion: { in: ESTADOS }

  scope :migraciones, -> { where(tipo: 'migracion') }
  scope :completadas, -> { where(estado: 'completada') }
end
