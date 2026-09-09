# == Schema Information
#
# Table name: helic3_tickets
#
#  id                       :bigint           not null, primary key
#  cerrada_at               :datetime
#  description              :text
#  plazo_respuesta_vence_at :datetime
#  pqrs_categoria           :string
#  pqrs_metadata            :jsonb
#  pqrs_numero_orden        :string
#  pqrs_prioridad           :string
#  pqrs_tipo                :string
#  radicada_at              :datetime
#  resolved_at              :datetime
#  respondida_at            :datetime
#  status                   :integer          default("open"), not null
#  title                    :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  assignee_id              :bigint
#  categoria_id             :bigint
#  conversation_id          :bigint
#  creator_id               :bigint
#  display_id               :integer          not null
#  etapa_id                 :bigint
#  motivo_pqr_id            :bigint
#  resultado_id             :bigint
#  tipo_id                  :bigint
#
# Indexes
#
#  idx_h3_tickets_categoria                            (categoria_id)
#  idx_h3_tickets_etapa                                (etapa_id)
#  idx_h3_tickets_motivo_pqr                           (motivo_pqr_id)
#  idx_h3_tickets_resultado                            (resultado_id)
#  idx_h3_tickets_tipo                                 (tipo_id)
#  index_helic3_tickets_on_account_id                  (account_id)
#  index_helic3_tickets_on_account_id_and_display_id   (account_id,display_id) UNIQUE
#  index_helic3_tickets_on_account_id_and_pqrs_tipo    (account_id,pqrs_tipo)
#  index_helic3_tickets_on_account_id_and_status       (account_id,status)
#  index_helic3_tickets_on_assignee_id_and_account_id  (assignee_id,account_id)
#  index_helic3_tickets_on_conversation_id             (conversation_id)
#
class Helic3::Ticket < ApplicationRecord
  belongs_to :account
  belongs_to :assignee, class_name: 'User', optional: true, inverse_of: :assigned_tickets
  belongs_to :creator, class_name: 'User', optional: true, inverse_of: :created_tickets
  belongs_to :conversation, optional: true

  # Clasificacion (EXP-01): las cinco llaves al vocabulario de CAT-01/CAT-02.
  # Todas opcionales porque un expediente nace sin clasificar y el agente lo
  # clasifica despues. Las columnas pqrs_* (clasificacion por strings de
  # julio) quedan legadas: estas llaves son la fuente de verdad.
  belongs_to :categoria, class_name: 'Helic3::Catalogo::Categoria', optional: true
  belongs_to :tipo, class_name: 'Helic3::Catalogo::Tipo', optional: true
  belongs_to :motivo_pqr, class_name: 'Helic3::Catalogo::MotivoPqr', optional: true
  belongs_to :resultado, class_name: 'Helic3::Catalogo::Resultado', optional: true
  belongs_to :etapa, class_name: 'Helic3::Catalogo::EtapaPqr', optional: true

  CATALOGOS_CLASIFICACION = %i[categoria tipo motivo_pqr resultado etapa].freeze

  # status es el estado operativo generico heredado del sistema de tickets de
  # julio; etapa es el estado del dominio con efecto legal, el que ve el
  # cliente. Conviven, y para plazos, semaforo e indicadores la fuente de
  # verdad es la ETAPA (decision escrita de EXP-01).
  enum status: { open: 0, pending: 1, resolved: 2, closed: 3 }

  validates :title, presence: true
  validates :account_id, presence: true
  validate :validate_assignee_belongs_to_account
  validate :validate_conversation_belongs_to_account
  validate :validate_catalogos_belong_to_account

  before_save :set_resolved_at
  after_create :load_attributes_created_by_db_triggers

  scope :latest, -> { order(created_at: :desc) }
  scope :assigned_to, ->(agent) { where(assignee_id: agent.id) }
  scope :unassigned, -> { where(assignee_id: nil) }
  # Conteo frente a la SIC: excluye las categorias sin radicado (Informacion).
  # Un expediente aun sin clasificar cuenta, hasta que se clasifique.
  scope :cuenta_para_sic, lambda {
    left_joins(:categoria).where(helic3_catalogo_categorias: { genera_radicado: [true, nil] })
  }

  def ticket_number
    "##{display_id}"
  end

  # Sella la respuesta al cliente y deja el expediente en la etapa que
  # detiene el reloj legal. La PQR se cierra aqui, sin esperar a que la
  # garantia termine (decision validada el 24/08).
  def responder!
    detiene = Helic3::Catalogo::EtapaPqr.activos.find_by!(account_id: account_id, detiene_reloj: true)
    update!(respondida_at: respondida_at || Time.current, etapa: detiene)
  end

  def reloj_detenido?
    respondida_at.present? || etapa&.detiene_reloj?
  end

  # La marca es dato del catalogo (genera_radicado), no un condicional por
  # codigo de categoria. Sin clasificar todavia, el expediente conserva su
  # numero: puede terminar siendo una PQR real.
  def genera_radicado?
    categoria.nil? || categoria.genera_radicado?
  end

  def numero_radicado
    ticket_number if genera_radicado?
  end

  # Los dos lectores del reloj (SEM-01). Derivados siempre: se guarda lo que
  # PASO (los sellos), se deriva lo que SIGNIFICA (cuanto queda y el color).
  # Congelamiento: respondido el expediente, la referencia deja de ser "hoy"
  # y pasa a ser el dia de la respuesta — la pregunta cambia de "cuanto
  # queda" a "cuanto quedaba al responder", sin almacenar ninguna copia.
  def dias_habiles_restantes
    return nil unless plazo_respuesta_vence_at && genera_radicado?

    calendario = Helic3::CalendarioHabil.new
    vence = fecha_bogota(plazo_respuesta_vence_at)
    referencia = fecha_de_referencia_del_reloj
    if vence >= referencia
      calendario.dias_habiles_entre(referencia, vence)
    else
      # vencido: el calendario no sabe de negativos, el expediente si.
      # "-3" es dato valido (vencido hace tres dias), no un error.
      -calendario.dias_habiles_entre(vence, referencia)
    end
  end

  # verde/amarillo/rojo contra los umbrales del ambito PQR (la escala del
  # indicador es proporcional al presupuesto que mide); nil si no hay reloj
  def semaforo
    restantes = dias_habiles_restantes
    return nil if restantes.nil?

    umbrales = Helic3::ParametrosGarantia.desde_catalogo(account, ambito: :pqr)
    if restantes >= umbrales.umbral_verde
      :verde
    elsif restantes >= umbrales.umbral_amarillo
      :amarillo
    else
      :rojo
    end
  end

  private

  def fecha_bogota(momento)
    momento.in_time_zone(Helic3::CalendarioHabil::ZONA).to_date
  end

  # la referencia del reloj: hoy mientras corre; el dia de la respuesta
  # cuando se detuvo (el sello respondida_at es el HECHO que ancla)
  def fecha_de_referencia_del_reloj
    if reloj_detenido? && respondida_at
      fecha_bogota(respondida_at)
    else
      Helic3::CalendarioHabil.hoy
    end
  end

  # display_id is set via a database trigger (per-account sequence),
  # same pattern used by Conversation. Fetch it back after create.
  def load_attributes_created_by_db_triggers
    self[:display_id] = self.class.find(id)[:display_id]
  end

  def set_resolved_at
    if status_changed? && (resolved? || closed?)
      self.resolved_at ||= Time.current
    elsif status_changed?
      self.resolved_at = nil
    end
  end

  def validate_assignee_belongs_to_account
    return if assignee_id.blank?
    return if account&.account_users&.exists?(user_id: assignee_id)

    errors.add(:assignee, 'must be an agent or administrator of the account')
  end

  def validate_conversation_belongs_to_account
    return if conversation_id.blank?
    return if conversation&.account_id == account_id

    errors.add(:conversation, 'must belong to the same account')
  end

  def validate_catalogos_belong_to_account
    CATALOGOS_CLASIFICACION.each do |asociacion|
      fila = public_send(asociacion)
      errors.add(asociacion, 'must belong to the same account') if fila && fila.account_id != account_id
    end
  end

  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('helic3_ticket_dpid_seq_' || NEW.account_id);"
  end
end

Helic3::Ticket.prepend_mod_with('Helic3::Ticket')
