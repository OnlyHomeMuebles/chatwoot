# frozen_string_literal: true

# CFG-01: agrega la pagina "Helic3 · Agentes IA" a Super Admin > Settings sin
# tocar app/controllers/super_admin/app_configs_controller.rb (upstream). Se
# engancha por prepend desde config/initializers/helic3_super_admin.rb, igual que
# lo hace el modulo enterprise con su propio controlador de app configs. Fuera de
# esta pagina todo pasa por super: General, Captain y las demas quedan intactas.
module Helic3::SuperAdmin::AppConfigsExtension
  PAGINA = 'helic3_ia'

  # Metadatos que pinta app/views/super_admin/app_configs/show.html.erb.
  CAMPOS = {
    Helic3::Agents::LlmRuntime::CLAVE_API_KEY => {
      'display_title' => 'OpenAI API Key',
      'description' => 'La usan los agentes de Helic3, el clasificador de PQR ' \
                       'y la base de conocimiento. El cambio aplica en el ' \
                       'siguiente mensaje, sin reiniciar.',
      'type' => 'secret'
    }
  }.freeze

  def show
    super
    @installation_configs.merge!(CAMPOS) if @config == PAGINA
  end

  private

  def allowed_configs
    return super unless @config == PAGINA

    @allowed_configs = CAMPOS.keys
  end
end
