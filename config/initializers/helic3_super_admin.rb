# frozen_string_literal: true

# CFG-01: engancha la pagina de IA de Helic3 en Super Admin sin tocar archivos
# upstream. to_prepare (no after_initialize) para que el prepend sobreviva a las
# recargas de Zeitwerk en desarrollo (mismo criterio que helic3_ticketable.rb).
Rails.application.config.to_prepare do
  SuperAdmin::AppConfigsController.prepend(Helic3::SuperAdmin::AppConfigsExtension)
  SuperAdmin::FeaturesHelper.singleton_class.prepend(Helic3::SuperAdmin::FeaturesExtension)
end
