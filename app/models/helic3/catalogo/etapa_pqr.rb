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

  # Una sola etapa inicial por cuenta (coherente con el indice unico parcial
  # idx_h3_etapa_inicial_unica). Al marcar una etapa como inicial, desmarca la que
  # lo estaba, para que el admin pueda re-apuntar la etapa inicial sin chocar con
  # el indice (que si no daria 500). update_all: sin callbacks, no reentra aqui; la
  # migracion usa update_columns y no dispara esto (maneja su propia coherencia).
  before_save :desmarcar_otras_iniciales, if: -> { inicial? && will_save_change_to_inicial? }

  private

  def desmarcar_otras_iniciales
    self.class.where(account_id: account_id, inicial: true).where.not(id: id).update_all(inicial: false)
  end
end
