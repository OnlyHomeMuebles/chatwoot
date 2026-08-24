# La falla fisica concreta del producto. Es un catalogo AUTONOMO (CAT-02,
# frente A): el detalle sale de la descripcion y las fotos, mientras que el
# motivo de garantia sale de una regla de fecha — "tela motosa" puede ocurrir
# a los 20 o a los 200 dias, bajo motivos distintos. La asociacion es
# opcional y de apoyo, nunca una pertenencia obligatoria.
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
#  motivo_garantia_id :bigint
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
                               inverse_of: :detalles_tipificados, optional: true
end
