# Un producto dentro del radicado de garantia (GAR-01). La clasificacion
# (motivo y detalle) y el estado (proceso) viven AQUI, nunca en la garantia:
# la cama puede ir a reparacion mientras al nochero se le niega la garantia,
# bajo el mismo numero de radicado.
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
