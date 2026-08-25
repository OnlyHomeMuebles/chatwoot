class Helic3::TicketPolicy < ApplicationPolicy
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
    admin_or_ticket_participant?
  end

  def assign?
    admin_or_ticket_participant?
  end

  def destroy?
    @account_user.administrator? || ticket_creator?
  end

  private

  # agents can only delete tickets they created themselves
  def ticket_creator?
    record.is_a?(Helic3::Ticket) && record.creator_id == @user.id
  end

  # status changes, edits and reassignment are limited to admins,
  # the ticket creator or the currently assigned agent
  def admin_or_ticket_participant?
    return true if @account_user.administrator?
    return false unless record.is_a?(Helic3::Ticket)

    [record.creator_id, record.assignee_id].compact.include?(@user.id)
  end
end

Helic3::TicketPolicy.prepend_mod_with('Helic3::TicketPolicy')
