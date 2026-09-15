# frozen_string_literal: true

# Adjunta las asociaciones de la entidad Ticket (Helic3::Ticket) a los modelos
# core de Chatwoot desde aquí, para no dejar líneas propias dentro de
# app/models/account.rb ni app/models/user.rb (cero huella upstream).
#
# to_prepare, NO after_initialize: en produccion (eager_load) ambos corren una
# sola vez y da lo mismo, pero en desarrollo Zeitwerk recarga User y Account en
# cada cambio de archivo, y esa recarga crea clases nuevas que pierden el
# include hecho en el boot. after_initialize no se repite; to_prepare si corre
# de nuevo en cada recarga, asi que la asociacion sobrevive.
Rails.application.config.to_prepare do
  Account.include(Helic3::AccountTicketable)
  User.include(Helic3::UserTicketable)
end
