# El radicado de garantia (GAR-01): cuelga del expediente y agrupa un item
# por producto reportado. Un solo numero, una sola fecha de apertura, un solo
# reloj de 30 dias habiles para todo el radicado; el seguimiento fino vive en
# los items (Helic3::GarantiaItem).
#
# ESTADO DERIVADO (decision de diseno del 27/08): el estado del radicado
# nunca se almacena — se deriva de los items en el momento de preguntarlo.
# Una copia almacenada puede mentir si un item avanza y la copia no se
# refresca; una derivada no tiene como desincronizarse.
class Helic3::Garantia < ApplicationRecord
  # plural espanol explicito: la regla latina de Rails para "-ia" (como
  # criteria) dejaria la tabla en singular
  self.table_name = 'helic3_garantias'

  # claves en helic3_catalogo_parametros; ninguna se siembra todavia porque
  # Only Home no ha decidido prefijo ni arranque del consecutivo (atado a la
  # migracion de historico). Sin configurar: sin prefijo y arranca en 1.
  PARAM_PREFIJO = 'radicado_garantia_prefijo'
  PARAM_INICIO = 'radicado_garantia_inicio' # lo lee el trigger al crear la secuencia

  belongs_to :account
  belongs_to :ticket, class_name: 'Helic3::Ticket'
  belongs_to :cobertura_ciudad, class_name: 'Helic3::Catalogo::CoberturaCiudad', optional: true
  has_many :items, class_name: 'Helic3::GarantiaItem', foreign_key: :garantia_id,
                   inverse_of: :garantia, dependent: :destroy

  validates :account_id, presence: true
  validate :validate_ticket_belongs_to_account

  before_validation :sellar_apertura_y_presupuesto, on: :create
  after_create :load_attributes_created_by_db_triggers

  scope :abiertas, -> { where(cerrada_at: nil) }

  # el numero unico visible al cliente, con el prefijo configurado (si lo hay)
  def numero_radicado
    "#{prefijo_radicado}#{display_id}"
  end

  # El estado visible es el del producto MAS ATRASADO: entre los items que
  # aun no estan en proceso terminal, el de posicion mas baja en el catalogo.
  # Un item todavia sin proceso es el mas atrasado de todos.
  def proceso_visible
    rezagado = items_pendientes.min_by { |item| item.proceso&.posicion || -1 }
    rezagado&.proceso
  end

  # Cierra cuando TODOS los productos estan resueltos (proceso es_terminal):
  # ni cuando se resuelve el principal, ni cuando se resuelve el primero.
  def resuelta?
    items.any? && items_pendientes.empty?
  end

  # sella el cierre administrativo; solo si todos los items ya resolvieron
  def cerrar!
    return false unless resuelta?

    update!(cerrada_at: cerrada_at || Time.current)
  end

  # El enganche del reloj (PLZ-01 calcula, aqui solo se guarda la apertura).
  # Recibe los parametros ya resueltos, igual que el propio PresupuestoGarantia.
  # Un proceso con plazo null (reparacion en fabrica) usa el saldo: el tope
  # del presupuesto lo aplica PLZ-01 con el clamp.
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
                                      .find_by(account_id: account_id, clave: 'plazo_total_garantia')
                                      &.valor_entero
  end

  def prefijo_radicado
    Helic3::Catalogo::Parametro.find_by(account_id: account_id, clave: PARAM_PREFIJO)&.valor
  end

  # display_id lo asigna el trigger (secuencia por cuenta, mismo patron del
  # expediente); se relee despues de crear
  def load_attributes_created_by_db_triggers
    self[:display_id] = self.class.find(id)[:display_id]
  end

  def validate_ticket_belongs_to_account
    return if ticket.nil? || ticket.account_id == account_id

    errors.add(:ticket, 'must belong to the same account')
  end

  trigger.before(:insert).for_each(:row) do
    <<~SQL.squish
      EXECUTE format('CREATE SEQUENCE IF NOT EXISTS helic3_garantia_dpid_seq_%s START WITH %s',
                     NEW.account_id,
                     COALESCE((SELECT valor::integer FROM helic3_catalogo_parametros
                               WHERE account_id = NEW.account_id
                                 AND clave = 'radicado_garantia_inicio'), 1));
      NEW.display_id := nextval('helic3_garantia_dpid_seq_' || NEW.account_id);
    SQL
  end
end
