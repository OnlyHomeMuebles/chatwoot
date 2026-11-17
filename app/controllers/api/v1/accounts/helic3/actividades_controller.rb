class Api::V1::Accounts::Helic3::ActividadesController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # POST /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/actividades
  #
  # ACT-01: registra el seguimiento de una persona. El autor es quien llama y la fecha
  # la pone el servidor (created_at): ninguna de las dos se acepta del cliente. Responde
  # el expediente, como las demas acciones, para que el panel se refresque.
  def create
    @ticket.actividades.create!(actividad_params.merge(autor: Current.user))
    render 'api/v1/accounts/helic3/tickets/show', formats: [:json]
  end

  private

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:ticket_id])
  end

  # registrar seguimiento no exige ser el asignado: basta con poder ver el expediente.
  def check_authorization
    authorize(@ticket, :show?)
  end

  def actividad_params
    params.require(:actividad).permit(:titulo, :detalle)
  end
end
