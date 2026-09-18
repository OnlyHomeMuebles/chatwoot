# Asociaciones de tickets para User (agente que crea o al que se asigna un ticket).
# Vive bajo helic3/; el include se hace desde config/initializers/helic3_ticketable.rb.
module Helic3::UserTicketable
  extend ActiveSupport::Concern

  included do
    has_many :assigned_tickets, foreign_key: 'assignee_id', class_name: 'Helic3::Ticket',
                                dependent: :nullify, inverse_of: :assignee
    has_many :created_tickets, foreign_key: 'creator_id', class_name: 'Helic3::Ticket',
                               dependent: :nullify, inverse_of: :creator
  end
end
