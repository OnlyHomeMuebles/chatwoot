class Api::V1::Accounts::Helic3::ResolucionesController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # POST /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/resolucion
  #
  # La UNICA puerta para registrar el resultado de una PQR. Delega en
  # Helic3::Casos::Resolver (RES-01): no hay logica de resolucion aqui, solo
  # traduccion — se resuelve el resultado contra la cuenta y se llama al servicio.
  # Endpoint propio (no update) porque resolver es un acto de dominio con reloj
  # legal, no una edicion de campos sueltos.
  def create
    @ticket = Helic3::Casos::Resolver.new(
      ticket: @ticket,
      resultado: resultado_de_cuenta,
      actor: Current.user,
      origen: :humano
    ).call
    render 'api/v1/accounts/helic3/tickets/show', formats: [:json]
  end

  private

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:ticket_id])
  end

  def check_authorization
    authorize(@ticket)
  end

  # Un resultado inexistente o de otra cuenta no existe aqui: RecordNotFound (404),
  # nunca el error de validacion del modelo sobre cuentas.
  def resultado_de_cuenta
    Helic3::Catalogo::Resultado.find_by!(account: Current.account, id: params.require(:resultado_id))
  end
end
