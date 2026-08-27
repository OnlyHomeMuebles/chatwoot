# Clasificacion de primer nivel: activa el flujo de atencion (CAT-01).
# == Schema Information
#
# Table name: helic3_catalogo_categorias
#
#  id         :bigint           not null, primary key
#  activo     :boolean          default(TRUE), not null
#  codigo     :string           not null
#  nombre     :string           not null
#  posicion   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  idx_h3cat_categorias_account         (account_id)
#  idx_h3cat_categorias_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::Categoria < ApplicationRecord
  # plural explicito: la regla latina de Rails (-ria como en "criteria")
  # dejaria la tabla en singular "categoria"
  self.table_name = 'helic3_catalogo_categorias'

  include Helic3::Catalogo::Comun

  has_many :motivos_pqr, class_name: 'Helic3::Catalogo::MotivoPqr', inverse_of: :categoria, dependent: :restrict_with_error
end
