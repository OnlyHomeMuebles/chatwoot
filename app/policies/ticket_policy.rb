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
    @account_user.administrator? || ticket_creator?
  end

  private

  # agents can only delete tickets they created themselves
  def ticket_creator?
    record.is_a?(Ticket) && record.creator_id == @user.id
  end
end

TicketPolicy.prepend_mod_with('TicketPolicy')
