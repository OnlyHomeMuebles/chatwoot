class Api::V1::Accounts::TicketsController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket, only: [:show, :update, :destroy, :assign]
  before_action :check_authorization

  def index
    @tickets = apply_filters(Current.account.tickets.includes(:assignee, :creator).latest)
  end

  def show; end

  def create
    @ticket = Current.account.tickets.new(ticket_params)
    @ticket.creator = Current.user
    @ticket.save!
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
    return scope unless params[:status].present? && Ticket.statuses.key?(params[:status])

    scope.where(status: params[:status])
  end

  # authorize the record when we have one so the policy can apply
  # per-ticket rules (e.g. agents deleting their own tickets)
  def check_authorization
    @ticket.present? ? authorize(@ticket) : super
  end

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:id])
  end

  def ticket_params
    params.require(:ticket).permit(:title, :description, :status, :assignee_id, :conversation_id)
  end
end
