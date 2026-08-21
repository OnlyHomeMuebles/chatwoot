# Con que se cierra el tramite. Sus marcas indican si el resultado cierra la
# PQR y/o abre un expediente de garantia.
# == Schema Information
#
# Table name: helic3_catalogo_resultados
#
#  id            :bigint           not null, primary key
#  abre_garantia :boolean          default(FALSE), not null
#  activo        :boolean          default(TRUE), not null
#  cierra_pqr    :boolean          default(FALSE), not null
#  codigo        :string           not null
#  nombre        :string           not null
#  posicion      :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  idx_h3cat_resultados_account         (account_id)
#  idx_h3cat_resultados_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::Resultado < ApplicationRecord
  include Helic3::Catalogo::Comun
end
