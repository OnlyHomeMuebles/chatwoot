# frozen_string_literal: true

# Adjunta las asociaciones de la entidad Ticket (Helic3::Ticket) a los modelos
# core de Chatwoot desde aquí, para no dejar líneas propias dentro de
# app/models/account.rb ni app/models/user.rb (cero huella upstream).
#
# to_prepare, no after_initialize: en desarrollo Rails RECARGA las clases en cada
# cambio de código, y Account/User se vuelven a definir sin el include. Con
# after_initialize (que corre una sola vez al arrancar) las asociaciones se
# pierden en la primera recarga y `Account#tickets` desaparece, lo que revienta el
# índice de tickets con 500 hasta reiniciar. to_prepare se re-ejecuta en cada
# recarga (y una sola vez en producción, que usa eager load), así el include
# nunca se pierde. include es idempotente: reaplicarlo no tiene costo.
Rails.application.config.to_prepare do
  Account.include(Helic3::AccountTicketable)
  User.include(Helic3::UserTicketable)
end
