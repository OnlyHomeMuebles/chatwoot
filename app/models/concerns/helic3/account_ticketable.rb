# Asociaciones de tickets para Account. Vive bajo helic3/ para no dispersar el
# código propio en el core; el modelo Account solo hace `include`.
module Helic3::AccountTicketable
  extend ActiveSupport::Concern

  included do
    has_many :tickets, class_name: 'Helic3::Ticket', dependent: :destroy_async
  end
end
