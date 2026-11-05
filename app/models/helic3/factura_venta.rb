# IND-03: una factura de venta de Siesa (columnas Nro documento, Desc. C.O.,
# Fecha, Valor subtotal, las unicas confirmadas del Dash CX). Alimenta Nº
# facturas/ratio/subtotal en Garantias; numero_documento es unico por cuenta
# (es la llave del modo "Sobrescribir / Actualizar").
# == Schema Information
#
# Table name: helic3_facturas_venta
#
#  id               :bigint           not null, primary key
#  centro_operacion :string
#  fecha            :date             not null
#  numero_documento :string           not null
#  valor_subtotal   :decimal(14, 2)   not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  carga_id         :bigint           not null
#
# Indexes
#
#  idx_h3_facturas_account         (account_id)
#  idx_h3_facturas_account_numero  (account_id,numero_documento) UNIQUE
#  idx_h3_facturas_carga           (carga_id)
#
# Foreign Keys
#
#  fk_rails_...  (carga_id => helic3_cargas.id)
#
class Helic3::FacturaVenta < ApplicationRecord
  self.table_name = 'helic3_facturas_venta'

  belongs_to :account
  belongs_to :carga, class_name: 'Helic3::Carga', inverse_of: :facturas

  validates :numero_documento, presence: true, uniqueness: { scope: :account_id }
  validates :fecha, presence: true
  validates :valor_subtotal, numericality: true
end
