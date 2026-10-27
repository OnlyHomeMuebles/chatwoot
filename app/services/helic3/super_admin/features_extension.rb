# frozen_string_literal: true

# CFG-01: agrega "Helic3 · Agentes IA" al submenu Settings y a las tarjetas de
# Super Admin sin tocar app/helpers/super_admin/features.yml (upstream).
# Vive en app/services y no en app/helpers porque Rails incluye todo
# app/helpers en todas las vistas (include_all_helpers).
module Helic3::SuperAdmin::FeaturesExtension
  def available_features
    pagina = Helic3::SuperAdmin::AppConfigsExtension::PAGINA
    super.merge(
      pagina => {
        'name' => 'Helic3 · Agentes IA',
        'description' => 'Llave de OpenAI de los agentes de Helic3.',
        'enabled' => true,
        'icon' => 'icon-robot-line',
        'config_key' => pagina
      }
    )
  end
end
