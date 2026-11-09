# frozen_string_literal: true

# CFG-01: agrega las tarjetas de Helic3 al submenu Settings de Super Admin sin tocar
# app/helpers/super_admin/features.yml (upstream). Vive en app/services y no en
# app/helpers porque Rails incluye todo app/helpers en todas las vistas
# (include_all_helpers). ERP-16 suma la tarjeta del ERP Siesa.
module Helic3::SuperAdmin::FeaturesExtension
  def available_features
    paginas = Helic3::SuperAdmin::AppConfigsExtension
    super.merge(
      paginas::PAGINA_IA => tarjeta(paginas::PAGINA_IA, 'Helic3 · Agentes IA',
                                    'Llave de OpenAI de los agentes de Helic3.', 'icon-robot-line'),
      paginas::PAGINA_ERP => tarjeta(paginas::PAGINA_ERP, 'Helic3 · ERP Siesa',
                                     'Conexión de Helic3 con el ERP Siesa.', 'icon-building-4-line')
    )
  end

  private

  def tarjeta(pagina, nombre, descripcion, icono)
    { 'name' => nombre, 'description' => descripcion, 'enabled' => true, 'icon' => icono, 'config_key' => pagina }
  end
end
