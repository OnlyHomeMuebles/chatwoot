# Un producto dentro del radicado de garantia (GAR-01). La clasificacion
# (motivo y detalle) y el estado (proceso) viven AQUI, nunca en la garantia:
# la cama puede ir a reparacion mientras al nochero se le niega la garantia,
# bajo el mismo numero de radicado.
# == Schema Information
#
# Table name: helic3_garantia_items
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
#  garantia_id           :bigint           not null
#  motivo_garantia_id    :bigint
#  proceso_id            :bigint
#
# Indexes
#
#  idx_h3_gitems_account   (account_id)
#  idx_h3_gitems_detalle   (detalle_tipificado_id)
#  idx_h3_gitems_garantia  (garantia_id)
#  idx_h3_gitems_motivo    (motivo_garantia_id)
#  idx_h3_gitems_proceso   (proceso_id)
#
# Foreign Keys
#
#  fk_rails_...  (detalle_tipificado_id => helic3_catalogo_detalles_tipificados.id)
#  fk_rails_...  (garantia_id => helic3_garantias.id)
#  fk_rails_...  (motivo_garantia_id => helic3_catalogo_motivos_garantia.id)
#  fk_rails_...  (proceso_id => helic3_catalogo_procesos_garantia.id)
#
class Helic3::GarantiaItem < ApplicationRecord
  belongs_to :account
  belongs_to :garantia, class_name: 'Helic3::Garantia', inverse_of: :items
  belongs_to :motivo_garantia, class_name: 'Helic3::Catalogo::MotivoGarantia', optional: true
  belongs_to :detalle_tipificado, class_name: 'Helic3::Catalogo::DetalleTipificado', optional: true
  belongs_to :proceso, class_name: 'Helic3::Catalogo::ProcesoGarantia', optional: true

  CATALOGOS_ITEM = %i[motivo_garantia detalle_tipificado proceso].freeze

  validates :producto_nombre, presence: true
  validate :validate_garantia_belongs_to_account
  validate :validate_catalogos_belong_to_account

  # Resuelto = en un proceso terminal del catalogo (es_terminal es DATO:
  # la garantia negada y el desistimiento resuelven al producto marcando
  # una fila, no reescribiendo esta regla).
  def resuelto?
    proceso&.es_terminal? || false
  end

  # avanza el producto de estado; al llegar a un proceso terminal sella la
  # fecha de resolucion (y la limpia si el proceso se corrige hacia atras)
  def avanzar_a!(nuevo_proceso, decision: nil)
    atributos = { proceso: nuevo_proceso }
    atributos[:decision] = decision if decision
    atributos[:resuelto_at] = nuevo_proceso&.es_terminal? ? (resuelto_at || Time.current) : nil
    update!(atributos)
  end

  private

  def validate_garantia_belongs_to_account
    return if garantia.nil? || garantia.account_id == account_id

    errors.add(:garantia, 'must belong to the same account')
  end

  def validate_catalogos_belong_to_account
    CATALOGOS_ITEM.each do |asociacion|
      fila = public_send(asociacion)
      errors.add(asociacion, 'must belong to the same account') if fila && fila.account_id != account_id
    end
  end
end
