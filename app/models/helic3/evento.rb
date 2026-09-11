# EVT-01: un evento de la bitacora del expediente. Guarda que paso, quien lo
# hizo, cuando y desde donde. El modelo solo persiste; quien decide QUE se
# registra son los servicios de dominio (Radicar, Resolver, AbrirGarantia...),
# que llaman a `registrar!` en sus puntos de transicion.
# == Schema Information
#
# Table name: helic3_eventos
#
#  id          :bigint           not null, primary key
#  origen      :string           not null
#  payload     :jsonb            not null
#  tipo        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  actor_id    :bigint
#  garantia_id :bigint
#  ticket_id   :bigint           not null
#
# Indexes
#
#  idx_h3_eventos_account   (account_id)
#  idx_h3_eventos_actor     (actor_id)
#  idx_h3_eventos_garantia  (garantia_id)
#  idx_h3_eventos_ticket    (ticket_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (actor_id => users.id)
#  fk_rails_...  (garantia_id => helic3_garantias.id)
#  fk_rails_...  (ticket_id => helic3_tickets.id)
#
class Helic3::Evento < ApplicationRecord
  # "evento" pluraliza mal con el inflector (eventoes); tabla explicita, igual
  # que Garantia y TicketDato con la regla latina.
  self.table_name = 'helic3_eventos'

  # lista cerrada de transiciones: son eventos del dominio, no valores de
  # catalogo que Karen edite, por eso viven en codigo.
  TIPOS = %w[radicada clasificada resultado_propuesto resultado_aplicado
             garantia_abierta proceso_avanzado respondida].freeze
  ORIGENES = %w[humano agente].freeze

  belongs_to :account
  belongs_to :ticket, class_name: 'Helic3::Ticket', inverse_of: :eventos
  belongs_to :garantia, class_name: 'Helic3::Garantia', optional: true
  # nulo cuando lo hace el agente: el agente no es un User del sistema
  belongs_to :actor, class_name: 'User', optional: true

  validates :tipo, inclusion: { in: TIPOS }
  validates :origen, inclusion: { in: ORIGENES }

  scope :cronologicos, -> { order(:created_at, :id) }

  # unico punto de escritura: la cuenta se deriva del ticket para no repetirla
  # en cada llamador. El actor y la garantia son opcionales. Los parametros son
  # los campos del evento (contrato de la bitacora), por eso se nombran todos.
  # rubocop:disable Metrics/ParameterLists
  def self.registrar!(ticket:, tipo:, origen:, actor: nil, garantia: nil, payload: {})
    create!(account: ticket.account, ticket: ticket, garantia: garantia,
            actor: actor, tipo: tipo, origen: origen.to_s, payload: payload)
  end
  # rubocop:enable Metrics/ParameterLists
end
