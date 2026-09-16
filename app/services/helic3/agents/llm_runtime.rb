# frozen_string_literal: true

# Fuente UNICA de la seleccion de proveedor / modelo / credenciales del LLM para
# todos los consumidores: el job del agente, el extractor de PQR y el rake de voz.
#
# Antes cada uno la resolvia por su lado —el job elegia Gemini > OpenAI > Groq >
# Ollama y el extractor entraba SIEMPRE por OpenAI—, asi que en un despliegue con
# Gemini y sin llave de OpenAI el extractor fallaba en silencio y la compuerta no
# radicaba nunca. Aqui decide un solo lugar y todos lo honran.
module Helic3::Agents::LlmRuntime
  DEFAULT_MODELS = { groq: 'llama-3.3-70b-versatile', gemini: 'gemini-flash-latest',
                     ollama: 'qwen2.5:14b' }.freeze
  GROQ_BASE = 'https://api.groq.com/openai/v1'
  GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/openai'
  OLLAMA_BASE = 'http://localhost:11434/v1'

  module_function

  # Proveedor activo: explicito por ONLY_HOME_LLM_PROVIDER, o el primero con
  # credencial disponible (Gemini > OpenAI > Groq), o el modelo local (Ollama).
  def provider
    explicit = ENV['ONLY_HOME_LLM_PROVIDER'].to_s.strip.downcase
    return explicit.to_sym if %w[ollama gemini groq openai].include?(explicit)
    return :gemini if ENV['GEMINI_API_KEY'].to_s.strip.present?
    return :openai if ENV['OPENAI_API_KEY'].to_s.strip.present?
    return :groq if ENV['GROQ_API_KEY'].to_s.strip.present?

    :ollama
  end

  def model(prov = provider)
    case prov
    when :groq then ENV.fetch('GROQ_MODEL', DEFAULT_MODELS[:groq])
    when :gemini then ENV.fetch('GEMINI_MODEL', DEFAULT_MODELS[:gemini])
    when :ollama then ENV.fetch('OLLAMA_MODEL', DEFAULT_MODELS[:ollama])
    else openai_model
    end
  end

  # El modelo de OpenAI se puede cambiar desde Super Admin (CAPTAIN_OPEN_AI_MODEL),
  # igual que el resto de agentes; si no, por ENV o el default del sistema.
  def openai_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
      ENV['ONLY_HOME_OPENAI_MODEL'].presence ||
      LlmConstants::DEFAULT_MODEL
  end

  # Credencial del proveedor activo. Ollama es un cliente openai-compatible local
  # que no requiere llave real; el resto puede venir vacio (y ahi el consumidor
  # debe registrar el error, no fallar en silencio).
  def api_key(prov = provider)
    case prov
    when :groq then ENV['GROQ_API_KEY'].presence
    when :gemini then ENV['GEMINI_API_KEY'].presence
    when :ollama then 'ollama'
    else ENV['OPENAI_API_KEY'].presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence
    end
  end

  # Endpoint openai-compatible del proveedor; nil para OpenAI (endpoint por defecto).
  def api_base(prov = provider)
    case prov
    when :groq then ENV.fetch('GROQ_API_BASE', GROQ_BASE)
    when :gemini then ENV.fetch('GEMINI_OPENAI_BASE', GEMINI_BASE)
    when :ollama then ENV.fetch('OLLAMA_API_BASE', OLLAMA_BASE)
    end
  end

  # Opciones para el gem ai-agents (RunnerService / *Agent.build).
  def agents_options
    prov = provider
    { model: model(prov), provider: prov == :ollama ? :ollama : :openai, assume_model_exists: true }
  end

  # Configura el gem ai-agents con las credenciales del proveedor activo.
  def configure_agents!
    prov = provider
    return Agents.configure { |c| c.ollama_api_base = api_base(:ollama) } if prov == :ollama

    base = api_base(prov)
    Agents.configure do |c|
      c.openai_api_key = api_key(prov)
      c.openai_api_base = base if base
    end
  end
end
