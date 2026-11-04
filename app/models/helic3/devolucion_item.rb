# Un producto dentro del radicado de devolucion (IND-06). La clasificacion
# (motivo propio de Devolucion) y el estado (proceso, detalle -- catalogos
# COMPARTIDOS con Garantia, ver 20261019190000) viven en el item, nunca en el
# radicado, mismo criterio que Helic3::GarantiaItem.
# == Schema Information
#
# Table name: helic3_devolucion_items
#
#  id                    :bigint           not null, primary key
#  decision              :string
#  producto_nombre       :string           not null
#  producto_referencia   :string
#  resuelto_at           :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  detalle_tipificado_id :bigint
#  devolucion_id         :bigint           not null
#  motivo_devolucion_id  :bigint
#  proceso_id            :bigint
#
# Indexes
#
#  idx_h3_ditems_account     (account_id)
#  idx_h3_ditems_detalle     (detalle_tipificado_id)
#  idx_h3_ditems_devolucion  (devolucion_id)
#  idx_h3_ditems_motivo      (motivo_devolucion_id)
#  idx_h3_ditems_proceso     (proceso_id)
#
# Foreign Keys
#
#  fk_rails_...  (detalle_tipificado_id => helic3_catalogo_detalles_tipificados.id)
#  fk_rails_...  (devolucion_id => helic3_devoluciones.id)
#  fk_rails_...  (motivo_devolucion_id => helic3_catalogo_motivos_devolucion.id)
#  fk_rails_...  (proceso_id => helic3_catalogo_procesos_garantia.id)
#
class Helic3::DevolucionItem < ApplicationRecord
  belongs_to :account
  belongs_to :devolucion, class_name: 'Helic3::Devolucion', inverse_of: :items
  belongs_to :motivo_devolucion, class_name: 'Helic3::Catalogo::MotivoDevolucion', optional: true
  belongs_to :detalle_tipificado, class_name: 'Helic3::Catalogo::DetalleTipificado', optional: true
  belongs_to :proceso, class_name: 'Helic3::Catalogo::ProcesoGarantia', optional: true

  CATALOGOS_ITEM = %i[motivo_devolucion detalle_tipificado proceso].freeze

  validates :producto_nombre, presence: true
  validate :validate_devolucion_belongs_to_account
  validate :validate_catalogos_belong_to_account

  def resuelto?
    proceso&.es_terminal? || false
  end

  def avanzar_a!(nuevo_proceso, decision: nil)
    atributos = { proceso: nuevo_proceso }
    atributos[:decision] = decision if decision
    atributos[:resuelto_at] = nuevo_proceso&.es_terminal? ? (resuelto_at || Time.current) : nil
    update!(atributos)
  end

  private

  def validate_devolucion_belongs_to_account
    return if devolucion.nil? || devolucion.account_id == account_id

    errors.add(:devolucion, 'must belong to the same account')
  end

  def validate_catalogos_belong_to_account
    CATALOGOS_ITEM.each do |asociacion|
      fila = public_send(asociacion)
      errors.add(asociacion, 'must belong to the same account') if fila && fila.account_id != account_id
    end
  end
end
