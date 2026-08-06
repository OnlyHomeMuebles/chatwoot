# frozen_string_literal: true

# Memoria conversacional del agente Only Home. Persiste el contexto del multiagente (historial de
# la conversación y agente activo) por conversación de Chatwoot, para que el agente RECUERDE el hilo
# entre mensajes en lugar de empezar una conversación nueva en cada mensaje entrante.
#
# Se guarda en Redis con expiración deslizante: mientras la conversación siga activa se mantiene, y
# se limpia sola tras un periodo de inactividad.
class OnlyHome::ConversationMemory
  # Claves del contexto del gem `ai-agents` que son serializables y sirven para continuar el hilo.
  # Se descartan `state` (trae el cliente HTTP, no serializable) y `last_updated` (Time).
  PERSISTED_KEYS = %i[conversation_history current_agent turn_count].freeze
  TTL = 3.days.to_i

  def initialize(account_id:, conversation_id:)
    @key = "only_home:agent_memory:#{account_id}:#{conversation_id}"
  end

  # Contexto guardado listo para pasar a RunnerService#run. Devuelve {} si es una conversación nueva.
  def load
    raw = Redis::Alfred.get(@key)
    return {} if raw.blank?

    context = JSON.parse(raw, symbolize_names: true)
    symbolize_roles!(context)
    context
  end

  # Guarda solo las claves serializables del contexto devuelto por el run, renovando la expiración.
  def save(context)
    return if context.blank?

    Redis::Alfred.set(@key, context.slice(*PERSISTED_KEYS).to_json, ex: TTL)
  end

  private

  # JSON.parse simboliza las CLAVES pero no los VALORES. El gem decide qué agente retoma el hilo
  # comparando `msg[:role] == :assistant`, así que los roles deben volver a ser símbolos.
  def symbolize_roles!(context)
    Array(context[:conversation_history]).each do |msg|
      msg[:role] = msg[:role].to_sym if msg[:role].is_a?(String)
    end
  end
end
