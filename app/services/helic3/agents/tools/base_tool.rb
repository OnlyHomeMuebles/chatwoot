# frozen_string_literal: true

require 'agents'

# Shared base for Only Home tools that act on a Chatwoot conversation through the Application API.
# Reads the target conversation id and (optionally) an injected client from the run state, and
# turns API failures into a readable message the agent can react to instead of crashing the run.
class Helic3::Agents::Tools::BaseTool < Agents::Tool
  private

  def conversation_id(tool_context)
    tool_context.state[:conversation_id] || raise(ArgumentError, 'conversation_id ausente en el contexto del run')
  end

  def client(tool_context)
    tool_context.state[:chatwoot_client] || Helic3::ChatwootClient.new
  end

  def with_api_error_handling
    yield
  rescue Helic3::ChatwootClient::ApiError => e
    "No se pudo completar la acción en Chatwoot: #{e.message}"
  end
end
