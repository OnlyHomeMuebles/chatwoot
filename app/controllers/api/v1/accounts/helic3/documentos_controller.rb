# EVI-02: consulta de solo lectura del archivo documental del expediente.
class Api::V1::Accounts::Helic3::DocumentosController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/documentos
  #
  # Sincronizacion perezosa antes de listar (EVI-02, punto 3 del cableado):
  # ninguna evidencia deberia faltar aqui aunque un webhook haya fallado.
  def index
    Helic3::Casos::VincularEvidencias.call(@ticket)
    @documentos = @ticket.documentos.order(:ocurrido_at)
  end

  private

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:ticket_id])
  end

  # leer documentos es lo mismo que leer el expediente: show? sobre el ticket.
  def check_authorization
    authorize(@ticket, :show?)
  end
end
