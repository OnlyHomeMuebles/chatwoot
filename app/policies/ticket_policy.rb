class TicketPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def assign?
    true
  end

  def destroy?
    @account_user.administrator? || ticket_owner?
  end

  private

  # agents can delete tickets they created or that are assigned to them
  def ticket_owner?
    record.is_a?(Ticket) && [record.creator_id, record.assignee_id].compact.include?(@user.id)
  end
end

TicketPolicy.prepend_mod_with('TicketPolicy')
