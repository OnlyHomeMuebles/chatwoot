# frozen_string_literal: true

# Adjunta las asociaciones de la entidad Ticket (Helic3::Ticket) a los modelos
# core de Chatwoot desde aquí, para no dejar líneas propias dentro de
# app/models/account.rb ni app/models/user.rb (cero huella upstream).
Rails.application.config.to_prepare do
  Account.include(Helic3::AccountTicketable)
  User.include(Helic3::UserTicketable)
end
