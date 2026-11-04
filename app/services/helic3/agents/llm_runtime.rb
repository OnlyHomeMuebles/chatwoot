# frozen_string_literal: true

# Fuente UNICA de la credencial, el endpoint y el modelo del LLM para todos los
# consumidores: el job del agente, el extractor de PQR, la base de conocimiento
# y los rakes de knowledge.
#
# CFG-01 (decision de Julian, 2-oct-2026): el unico proveedor es OpenAI y la llave
# vive en Super Admin > Settings > Helic3 · Agentes IA (installation_configs,
# HELIC3_OPENAI_API_KEY). No se lee de variables de entorno ni de Captain.
module Helic3::Agents::LlmRuntime
  CLAVE_API_KEY = 'HELIC3_OPENAI_API_KEY'
  # Explicito para no heredar CAPTAIN_OPEN_AI_ENDPOINT, que el initializer
  # upstream ai_agents.rb y Llm::Config aplican de forma global.
  API_BASE = "#{LlmConstants::OPENAI_API_ENDPOINT}/v1".freeze
  SIN_LLAVE = '[Helic3] Sin llave de OpenAI: configurela en ' \
              'Super Admin > Settings > Helic3 · Agentes IA'

  module_function

  # GlobalConfig cachea en Redis y la cache se limpia al guardar desde Super Admin
  # (InstallationConfig#after_commit): el cambio aplica en el siguiente mensaje.
  def api_key
    GlobalConfig.get_value(CLAVE_API_KEY).presence
  end

  def api_base
    API_BASE
  end

  # Seleccion de modelo sin cambios respecto a antes de CFG-01 (fuera de alcance).
  def model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
      ENV['ONLY_HOME_OPENAI_MODEL'].presence ||
      LlmConstants::DEFAULT_MODEL
  end

  # Opciones para el gem ai-agents (RunnerService / *Agent.build).
  def agents_options
    { model: model, provider: :openai, assume_model_exists: true }
  end

  # Configura el gem ai-agents con la llave vigente. Sin llave no se falla en
  # silencio: queda el error en el log y el job responde su mensaje de respaldo.
  def configure_agents!
    key = api_key
    Rails.logger.error(SIN_LLAVE) if key.blank?

    Agents.configure do |config|
      config.openai_api_key = key
      config.openai_api_base = API_BASE
    end
  end
end
