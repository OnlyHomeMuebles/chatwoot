class Api::V1::Accounts::Helic3::DatosController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # PATCH /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/datos
  #
  # El operador confirma o corrige la ficha del caso desde el panel. Lo que toca
  # aqui queda con fuente 'humano' (la mas alta): ni la IA ni el ERP lo pisan
  # despues. La regla de precedencia vive en Helic3::Casos::RegistrarDatos, aqui
  # solo se traduce y se fija la fuente.
  def update
    Helic3::Casos::RegistrarDatos.new(ticket: @ticket, campos: campos_de_cuenta, fuente: :humano).call
    render 'api/v1/accounts/helic3/tickets/show', formats: [:json]
  end

  private

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:ticket_id])
  end

  # editar la ficha es un acto operativo (no el resultado legal): lo puede hacer
  # quien participa del expediente, igual que cualquier edicion (update?).
  def check_authorization
    authorize(@ticket, :update?)
  end

  # solo los campos de la ficha; un detalle_tipificado de otra cuenta no existe
  # aqui: RecordNotFound (404), igual que con el resultado en resoluciones.
  def campos_de_cuenta
    permitidos = params.fetch(:datos, {}).permit(:cedula, :direccion, :ciudad, :factura_numero,
                                                 :producto_nombre, :detalle_tipificado_id)
    if permitidos[:detalle_tipificado_id].present?
      Helic3::Catalogo::DetalleTipificado.find_by!(account: Current.account,
                                                   id: permitidos[:detalle_tipificado_id])
    end
    permitidos
  end
end
