# El radicado de devolucion (IND-06): expediente hermano de Garantia (mismo
# patron de GAR-01) -- cuelga del ticket y agrupa un item por producto
# devuelto. Un solo numero, una sola fecha de apertura, un solo reloj de 30
# dias habiles para todo el radicado (mismo presupuesto ya aprobado de
# Garantia, reusado: no hay un plazo distinto documentado para Devoluciones).
#
# ESTADO DERIVADO: igual que Garantia, el estado del radicado nunca se
# almacena -- se deriva de los items en el momento de preguntarlo.
# == Schema Information
#
# Table name: helic3_devoluciones
#
#  id                       :bigint           not null, primary key
#  abierta_at               :datetime         not null
#  cerrada_at               :datetime
#  presupuesto_dias_habiles :integer
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  cobertura_ciudad_id      :bigint
#  display_id               :integer          not null
#  ticket_id                :bigint           not null
#
# Indexes
#
#  idx_h3_devoluciones_account       (account_id)
#  idx_h3_devoluciones_account_dpid  (account_id,display_id) UNIQUE
#  idx_h3_devoluciones_cobertura     (cobertura_ciudad_id)
#  idx_h3_devoluciones_ticket        (ticket_id)
#
# Foreign Keys
#
#  fk_rails_...  (cobertura_ciudad_id => helic3_catalogo_coberturas_ciudad.id)
#  fk_rails_...  (ticket_id => helic3_tickets.id)
#
class Helic3::Devolucion < ApplicationRecord
  self.table_name = 'helic3_devoluciones'

  PARAM_PREFIJO = 'radicado_devolucion_prefijo'.freeze
  PARAM_INICIO = 'radicado_devolucion_inicio'.freeze # lo lee el trigger al crear la secuencia

  belongs_to :account
  belongs_to :ticket, class_name: 'Helic3::Ticket'
  belongs_to :cobertura_ciudad, class_name: 'Helic3::Catalogo::CoberturaCiudad', optional: true
  has_many :items, class_name: 'Helic3::DevolucionItem',
                   inverse_of: :devolucion, dependent: :destroy

  validates :account_id, presence: true
  validate :validate_ticket_belongs_to_account

  before_validation :sellar_apertura_y_presupuesto, on: :create
  after_create :load_attributes_created_by_db_triggers

  scope :abiertas, -> { where(cerrada_at: nil) }

  def numero_radicado
    "#{prefijo_radicado}#{display_id}"
  end

  def proceso_visible
    rezagado = items_pendientes.min_by { |item| item.proceso&.posicion || -1 }
    rezagado&.proceso
  end

  def resuelta?
    items.any? && items_pendientes.empty?
  end

  def cerrar!
    return false unless resuelta?

    update!(cerrada_at: cerrada_at || Time.current)
  end

  def presupuesto(parametros:, calendario: Helic3::CalendarioHabil.new)
    Helic3::PresupuestoGarantia.new(
      fecha_inicio: abierta_at,
      plazo_etapa_vigente: proceso_visible&.plazo_dias_habiles || parametros.total_dias,
      parametros: parametros,
      calendario: calendario
    )
  end

  private

  def items_pendientes
    items.reject(&:resuelto?)
  end

  def sellar_apertura_y_presupuesto
    self.abierta_at ||= Time.current
    self.presupuesto_dias_habiles ||= Helic3::Catalogo::Parametro
                                      .find_by(account_id: account_id, clave: 'plazo_total_devolucion')
                                      &.valor_entero
  end

  def prefijo_radicado
    Helic3::Catalogo::Parametro.find_by(account_id: account_id, clave: PARAM_PREFIJO)&.valor
  end

  def load_attributes_created_by_db_triggers
    self[:display_id] = self.class.find(id)[:display_id]
  end

  def validate_ticket_belongs_to_account
    return if ticket.nil? || ticket.account_id == account_id

    errors.add(:ticket, 'must belong to the same account')
  end

  trigger.before(:insert).for_each(:row) do
    <<~SQL.squish
      EXECUTE format('CREATE SEQUENCE IF NOT EXISTS helic3_devolucion_dpid_seq_%s START WITH %s',
                     NEW.account_id,
                     COALESCE((SELECT valor::integer FROM helic3_catalogo_parametros
                               WHERE account_id = NEW.account_id
                                 AND clave = 'radicado_devolucion_inicio'), 1));
      NEW.display_id := nextval('helic3_devolucion_dpid_seq_' || NEW.account_id);
    SQL
  end
end
