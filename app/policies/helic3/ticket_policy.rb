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

  # resolver es un acto con efecto legal: sella respondida_at, detiene el reloj
  # ante la SIC y sera el gancho que abra garantia (GAR-02). Mas estricto que un
  # cambio de estado operativo, por eso NO reusa update?. La puerta del AGENTE
  # (tool de AGT-03) no pasa por aqui: su limite es autonomia_resolver_pqr.
  def resolver?
    @account_user.administrator?
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
