# Si la ciudad tiene tecnico propio y por donde arranca la ruta de atencion.
# Decide si un caso de garantia pasa por visita tecnica o va directo a otra
# via (recoleccion, cambio).
# == Schema Information
#
# Table name: helic3_catalogo_coberturas_ciudad
#
#  id             :bigint           not null, primary key
#  activo         :boolean          default(TRUE), not null
#  codigo         :string           not null
#  nombre         :string           not null
#  origen_ruta    :string
#  posicion       :integer          default(0), not null
#  tecnico_propio :boolean          default(FALSE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  idx_h3cat_coberturas_ciudad_account         (account_id)
#  idx_h3cat_coberturas_ciudad_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::CoberturaCiudad < ApplicationRecord
  # plural espanol explicito: Rails generaria "cobertura_ciudads"
  self.table_name = 'helic3_catalogo_coberturas_ciudad'

  include Helic3::Catalogo::Comun
end
