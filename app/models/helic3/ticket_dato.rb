# DAT-01: la ficha del caso, 1:1 con el expediente. Guarda los datos
# recolectados (cedula, direccion, ciudad, factura, producto, detalle y —MAN-01—
# cliente_nombre/telefono/email, producto_referencia y factura_fecha) y en el
# jsonb `fuentes` de donde salio cada uno (ia/erp/humano). La regla de quien
# pisa a quien vive en Helic3::Casos::RegistrarDatos, no aqui: este modelo solo
# guarda. Tabla lateral a proposito: helic3_tickets no recibe columnas nuevas.
# == Schema Information
#
# Table name: helic3_ticket_datos
#
#  id                    :bigint           not null, primary key
#  cedula                :string
#  ciudad                :string
#  cliente_email         :string
#  cliente_nombre        :string
#  cliente_telefono      :string
#  direccion             :string
#  factura_fecha         :date
#  factura_numero        :string
#  fuentes               :jsonb            not null
#  producto_nombre       :string
#  producto_referencia   :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  detalle_tipificado_id :bigint
#  ticket_id             :bigint           not null
#
# Indexes
#
#  idx_h3_ticket_datos_account  (account_id)
#  idx_h3_ticket_datos_detalle  (detalle_tipificado_id)
#  idx_h3_ticket_datos_ticket   (ticket_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (detalle_tipificado_id => helic3_catalogo_detalles_tipificados.id)
#  fk_rails_...  (ticket_id => helic3_tickets.id)
#
class Helic3::TicketDato < ApplicationRecord
  # "dato" pluraliza mal con el inflector (datoes); tabla explicita, igual que
  # Garantia con la regla latina.
  self.table_name = 'helic3_ticket_datos'

  # los campos recolectados; la clave en `fuentes` es el nombre de la columna.
  # El detalle se guarda por id (es catalogo), el resto es texto libre del caso.
  # MAN-01 suma los datos del cliente y la compra (para la PQR manual sin chat).
  CAMPOS = %i[
    cedula direccion ciudad factura_numero producto_nombre detalle_tipificado_id
    cliente_nombre cliente_telefono cliente_email producto_referencia factura_fecha
  ].freeze

  belongs_to :account
  belongs_to :ticket, class_name: 'Helic3::Ticket', inverse_of: :datos
  belongs_to :detalle_tipificado, class_name: 'Helic3::Catalogo::DetalleTipificado', optional: true

  # MAN-01: la fecha de compra no puede ser futura. Va en el modelo (no solo en el
  # create del controlador) para que tambien aplique al editar la ficha por
  # PATCH /datos (MAN-03). allow_nil: la ficha casi siempre nace sin ella.
  validates :factura_fecha,
            comparison: { less_than_or_equal_to: ->(_record) { Date.current } },
            allow_nil: true

  validate :validate_ticket_belongs_to_account
  validate :validate_detalle_belongs_to_account

  private

  def validate_ticket_belongs_to_account
    return if ticket.nil? || ticket.account_id == account_id

    errors.add(:ticket, 'must belong to the same account')
  end

  def validate_detalle_belongs_to_account
    return if detalle_tipificado.nil? || detalle_tipificado.account_id == account_id

    errors.add(:detalle_tipificado, 'must belong to the same account')
  end
end
