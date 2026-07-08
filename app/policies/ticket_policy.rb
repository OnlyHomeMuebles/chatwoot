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
    @account_user.administrator?
  end
end

TicketPolicy.prepend_mod_with('TicketPolicy')
