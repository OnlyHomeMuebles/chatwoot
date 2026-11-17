# ACT-01: una actividad de seguimiento que una persona registra en el expediente
# (titulo + detalle). La fecha es created_at y el autor el usuario que la crea; las
# pone el servidor. No se editan ni se borran: quedan como registro del caso.
# == Schema Information
#
# Table name: helic3_actividades
#
#  id           :bigint           not null, primary key
#  autor_nombre :string
#  detalle      :text             not null
#  titulo       :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  autor_id     :bigint
#  ticket_id    :bigint           not null
#
# Indexes
#
#  idx_h3_actividades_account       (account_id)
#  idx_h3_actividades_autor         (autor_id)
#  idx_h3_actividades_ticket_fecha  (ticket_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (autor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (ticket_id => helic3_tickets.id) ON DELETE => cascade
#
class Helic3::Actividad < ApplicationRecord
  # "actividad" pluraliza mal con el inflector (actividads); tabla explicita, igual
  # que Evento y Garantia.
  self.table_name = 'helic3_actividades'

  TITULO_MAXIMO = 120
  DETALLE_MAXIMO = 2000

  belongs_to :account
  belongs_to :ticket, class_name: 'Helic3::Ticket', inverse_of: :actividades
  # nulo si el usuario se borra en Chatwoot (on_delete: :nullify); queda autor_nombre
  belongs_to :autor, class_name: 'User', optional: true

  validates :titulo, presence: true, length: { maximum: TITULO_MAXIMO }
  validates :detalle, presence: true, length: { maximum: DETALLE_MAXIMO }

  before_validation :tomar_datos_del_contexto, on: :create

  scope :recientes, -> { order(created_at: :desc, id: :desc) }

  private

  # la cuenta sale del expediente y el nombre es una instantanea del autor, para no
  # perder quien hizo el seguimiento si el usuario se borra despues.
  def tomar_datos_del_contexto
    self.account ||= ticket&.account
    self.autor_nombre ||= autor&.name
  end
end
