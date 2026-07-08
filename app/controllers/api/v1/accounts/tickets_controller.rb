class Api::V1::Accounts::TicketsController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket, only: [:show, :update, :destroy, :assign]
  before_action :check_authorization

  def index
    @tickets = Current.account.tickets.includes(:assignee, :creator).latest
    @tickets = @tickets.where(status: params[:status]) if params[:status].present? && Ticket.statuses.key?(params[:status])
    @tickets = @tickets.assigned_to(Current.user) if params[:mine].present?
    @tickets = @tickets.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
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

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:id])
  end

  def ticket_params
    params.require(:ticket).permit(:title, :description, :status, :assignee_id, :conversation_id)
  end
end
