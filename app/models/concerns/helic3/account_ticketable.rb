# Asociaciones de tickets para Account. Vive bajo helic3/ para no dispersar el
# código propio en el core; el include se hace desde config/initializers/helic3_ticketable.rb (cero huella en el core).
module Helic3::AccountTicketable
  extend ActiveSupport::Concern

  included do
    has_many :tickets, class_name: 'Helic3::Ticket', dependent: :destroy_async
  end
end
