# El estado con efecto legal de la PQR, el que ve el cliente. detiene_reloj
# marca las etapas que pausan el plazo legal (pendiente de confirmar cuales).
# == Schema Information
#
# Table name: helic3_catalogo_etapas_pqr
#
#  id              :bigint           not null, primary key
#  activo          :boolean          default(TRUE), not null
#  codigo          :string           not null
#  detiene_reloj   :boolean          default(FALSE), not null
#  nombre          :string           not null
#  posicion        :integer          default(0), not null
#  visible_cliente :boolean          default(TRUE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  idx_h3cat_etapas_pqr_account         (account_id)
#  idx_h3cat_etapas_pqr_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::EtapaPqr < ApplicationRecord
  # plural espanol explicito: Rails generaria "etapa_pqrs"
  self.table_name = 'helic3_catalogo_etapas_pqr'

  include Helic3::Catalogo::Comun
end
