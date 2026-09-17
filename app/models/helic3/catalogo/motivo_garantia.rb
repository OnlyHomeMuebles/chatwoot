# Que paso con el producto. Se asigna por regla parametrizada en dias
# (criterio 7): "reparacion primera entrega" hasta 30 dias inclusive desde la
# entrega, "calidad producto comprado" desde el dia 31. La regla y su
# parametro son datos, no codigo.
# == Schema Information
#
# Table name: helic3_catalogo_motivos_garantia
#
#  id             :bigint           not null, primary key
#  activo         :boolean          default(TRUE), not null
#  codigo         :string           not null
#  nombre         :string           not null
#  parametro_dias :integer
#  posicion       :integer          default(0), not null
#  regla          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  idx_h3cat_motivos_garantia_account         (account_id)
#  idx_h3cat_motivos_garantia_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::MotivoGarantia < ApplicationRecord
  # plural espanol explicito: Rails generaria "motivo_garantia" -> "motivo_garantias"
  self.table_name = 'helic3_catalogo_motivos_garantia'

  include Helic3::Catalogo::Comun

  has_many :detalles_tipificados, class_name: 'Helic3::Catalogo::DetalleTipificado', inverse_of: :motivo_garantia,
                                  dependent: :restrict_with_error

  validates :parametro_dias, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
