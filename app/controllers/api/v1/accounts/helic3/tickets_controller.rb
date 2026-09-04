class Api::V1::Accounts::Helic3::TicketsController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket, only: [:show, :update, :destroy, :assign]
  before_action :check_authorization

  def index
    @tickets = apply_filters(
      Current.account.tickets.includes(:assignee, :creator, :categoria, :tipo, :motivo_pqr, :resultado, :etapa).latest
    )
  end

  def show; end

  # Nace por Helic3::Casos::Radicar (CAS-01): la unica puerta de radicacion, para
  # que un expediente creado desde el panel arranque con su reloj corriendo igual
  # que uno creado por el agente. La categoria la deriva el servicio del motivo;
  # no se envia desde aqui.
  def create
    @ticket = Helic3::Casos::Radicar.new(
      account: Current.account,
      titulo: ticket_params[:title],
      descripcion: ticket_params[:description],
      conversation_id: ticket_params[:conversation_id],
      tipo: catalogo_de_cuenta(Helic3::Catalogo::Tipo, ticket_params[:tipo_id]),
      motivo_pqr: catalogo_de_cuenta(Helic3::Catalogo::MotivoPqr, ticket_params[:motivo_pqr_id]),
      creator: Current.user,
      origen: :humano
    ).call
  end

  def update
    @ticket.update!(ticket_params)
  end

  def destroy
    @ticket.destroy!
    head :ok
  end

  def assign
    assignee = params[:assignee_id].present? ? Current.account.users.find(params[:assignee_id]) : nil
    @ticket.update!(assignee: assignee)
    render :show
  end

  private

  def apply_filters(scope)
    scope = filter_by_status(scope)
    scope = scope.assigned_to(Current.user) if params[:mine].present?
    scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    scope = scope.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    scope
  end

  def filter_by_status(scope)
    return scope unless params[:status].present? && Helic3::Ticket.statuses.key?(params[:status])

    scope.where(status: params[:status])
  end

  # authorize the record when we have one so the policy can apply
  # per-ticket rules (e.g. agents deleting their own tickets)
  def check_authorization
    @ticket.present? ? authorize(@ticket) : authorize(Helic3::Ticket)
  end

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:id])
  end

  # Resuelve un catalogo por id acotado a la cuenta: un id de otra cuenta no
  # existe aqui y se rechaza (RecordNotFound). Nulo cuando no se envio.
  def catalogo_de_cuenta(modelo, id)
    return if id.blank?

    modelo.find_by!(account: Current.account, id: id)
  end

  def ticket_params
    params.require(:ticket).permit(:title, :description, :status, :assignee_id, :conversation_id,
                                   :categoria_id, :tipo_id, :motivo_pqr_id, :resultado_id, :etapa_id)
  end
end
