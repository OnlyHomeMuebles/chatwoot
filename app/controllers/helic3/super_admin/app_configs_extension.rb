# frozen_string_literal: true

# CFG-01: agrega las paginas de Helic3 a Super Admin > Settings sin tocar
# app/controllers/super_admin/app_configs_controller.rb (upstream). Se engancha por
# prepend desde config/initializers/helic3_super_admin.rb, igual que lo hace el modulo
# enterprise con su propio controlador de app configs. Fuera de estas paginas todo pasa
# por super: General, Captain y las demas quedan intactas.
#
# ERP-16: de una sola pagina (Agentes IA) a un mapa de paginas, cada una con sus campos.
module Helic3::SuperAdmin::AppConfigsExtension
  PAGINA_IA = 'helic3_ia'
  PAGINA_ERP = 'helic3_erp'

  # Metadatos que pinta app/views/super_admin/app_configs/show.html.erb.
  CAMPOS_IA = {
    Helic3::Agents::LlmRuntime::CLAVE_API_KEY => {
      'display_title' => 'OpenAI API Key',
      'description' => 'La usan los agentes de Helic3, el clasificador de PQR ' \
                       'y la base de conocimiento. El cambio aplica en el ' \
                       'siguiente mensaje, sin reiniciar.',
      'type' => 'secret'
    },
    Helic3::Agents::LlmRuntime::CLAVE_MODELO_VISION => {
      'display_title' => 'Modelo de visión para imágenes',
      'description' => 'Si lo configuras (p. ej. gpt-6.1-terra), el agente lee las ' \
                       'imágenes (facturas, fotos del producto) con ese modelo de ' \
                       'visión en vez del OCR local. Déjalo vacío para usar el OCR. ' \
                       'El cambio aplica en el siguiente mensaje, sin reiniciar.',
      'type' => 'text'
    }
  }.freeze

  CAMPOS_ERP = {
    Helic3::Erp::CLAVE_MODO => {
      'display_title' => 'Modo del ERP',
      'description' => 'Desactivado: no se consulta el ERP y todo se llena a mano. Simulado: ' \
                       'clientes de prueba, nunca en producción. Siesa: consulta Siesa HUB con ' \
                       'la conexión de abajo. El cambio aplica en la siguiente consulta, sin reiniciar.',
      'type' => 'select',
      'options' => { 'desactivado' => 'Desactivado', 'simulado' => 'Simulado', 'siesa' => 'Siesa' }
    },
    Helic3::Erp::CLAVE_BASE_URL => {
      'display_title' => 'URL base de Siesa HUB',
      'description' => 'Sin la ruta de la consulta (p. ej. https://apiqa.siesacloud.com).',
      'type' => 'text'
    },
    Helic3::Erp::CLAVE_CLIENT_ID => { 'display_title' => 'Client ID (Apigee)', 'type' => 'secret' },
    Helic3::Erp::CLAVE_CONNI_KEY => { 'display_title' => 'ConniKey', 'type' => 'secret' },
    Helic3::Erp::CLAVE_CONNI_TOKEN => { 'display_title' => 'ConniToken', 'type' => 'secret' },
    Helic3::Erp::CLAVE_ID_COMPANIA => { 'display_title' => 'Compañía', 'type' => 'text' },
    Helic3::Erp::CLAVE_CONSULTA_CLIENTES => {
      'display_title' => 'Consulta de clientes',
      'description' => 'Nombre de la consulta de Siesa HUB que trae nombre y contacto por cédula.',
      'type' => 'text'
    },
    Helic3::Erp::CLAVE_CONSULTA_COMPRAS => {
      'display_title' => 'Consultas de compras (separadas por coma)',
      'description' => 'Una o varias consultas de facturas, separadas por coma ' \
                       '(p. ej. API_v2_Ventas_Facturas_DesdePedido).',
      'type' => 'text'
    }
  }.freeze

  PAGINAS = { PAGINA_IA => CAMPOS_IA, PAGINA_ERP => CAMPOS_ERP }.freeze

  def show
    super
    @installation_configs.merge!(PAGINAS[@config]) if PAGINAS.key?(@config)
  end

  private

  def allowed_configs
    return super unless PAGINAS.key?(@config)

    @allowed_configs = PAGINAS[@config].keys
  end
end
