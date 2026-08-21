# La falla fisica concreta del producto. Nunca existe sin su motivo de
# garantia asociado (criterio 3 de CAT-01).
# == Schema Information
#
# Table name: helic3_catalogo_detalles_tipificados
#
#  id                 :bigint           not null, primary key
#  activo             :boolean          default(TRUE), not null
#  codigo             :string           not null
#  nombre             :string           not null
#  posicion           :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  motivo_garantia_id :bigint           not null
#
# Indexes
#
#  idx_h3cat_detalles_motivo                      (motivo_garantia_id)
#  idx_h3cat_detalles_tipificados_account         (account_id)
#  idx_h3cat_detalles_tipificados_account_codigo  (account_id,codigo) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (motivo_garantia_id => helic3_catalogo_motivos_garantia.id)
#
class Helic3::Catalogo::DetalleTipificado < ApplicationRecord
  # plural espanol explicito: Rails generaria "detalle_tipificados"
  self.table_name = 'helic3_catalogo_detalles_tipificados'

  include Helic3::Catalogo::Comun

  belongs_to :motivo_garantia, class_name: 'Helic3::Catalogo::MotivoGarantia',
                               inverse_of: :detalles_tipificados
end
