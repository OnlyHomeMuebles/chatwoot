# La P, la Q y la R: peticion, queja, reclamo, sugerencia o felicitacion.
# Define el plazo legal de respuesta (dato, no constante; queda null hasta
# que el area confirme los plazos por tipo).
# == Schema Information
#
# Table name: helic3_catalogo_tipos
#
#  id                 :bigint           not null, primary key
#  activo             :boolean          default(TRUE), not null
#  codigo             :string           not null
#  nombre             :string           not null
#  plazo_dias_habiles :integer
#  posicion           :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  idx_h3cat_tipos_account         (account_id)
#  idx_h3cat_tipos_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::Tipo < ApplicationRecord
  include Helic3::Catalogo::Comun

  validates :plazo_dias_habiles, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
