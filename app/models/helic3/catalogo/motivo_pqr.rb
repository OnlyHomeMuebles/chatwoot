# Que esta pidiendo el cliente. Cada motivo pertenece a una categoria y su
# marca abre_garantia decide si el caso deriva un expediente de garantia.
# == Schema Information
#
# Table name: helic3_catalogo_motivos_pqr
#
#  id            :bigint           not null, primary key
#  abre_garantia :boolean          default(FALSE), not null
#  activo        :boolean          default(TRUE), not null
#  codigo        :string           not null
#  nombre        :string           not null
#  posicion      :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  categoria_id  :bigint           not null
#
# Indexes
#
#  idx_h3cat_motivos_pqr_account         (account_id)
#  idx_h3cat_motivos_pqr_account_codigo  (account_id,codigo) UNIQUE
#  idx_h3cat_motivos_pqr_categoria       (categoria_id)
#
# Foreign Keys
#
#  fk_rails_...  (categoria_id => helic3_catalogo_categorias.id)
#
class Helic3::Catalogo::MotivoPqr < ApplicationRecord
  # plural espanol explicito: Rails generaria "motivo_pqrs"
  self.table_name = 'helic3_catalogo_motivos_pqr'

  include Helic3::Catalogo::Comun

  belongs_to :categoria, class_name: 'Helic3::Catalogo::Categoria', inverse_of: :motivos_pqr
end
