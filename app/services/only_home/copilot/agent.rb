# frozen_string_literal: true

# The Only Home Copilot agent: assists the HUMAN support agent (not the customer). Given a
# conversation, it can draft replies, summarize the case, suggest next steps, or answer the
# agent's questions. It reads the conversation with GetConversationTool before suggesting.
# Own implementation on the ai-agents gem (mirrors Captain's Copilot, different code).
class OnlyHome::Copilot::Agent
  INSTRUCTIONS = <<~INST
    Eres el Copiloto de Only Home. Asistes al AGENTE HUMANO de soporte, NO al cliente.
    Tu trabajo es ayudarle a atender la conversación: redactar borradores de respuesta,
    resumir el caso, sugerir próximos pasos o responder sus dudas sobre la conversación.

    Antes de sugerir, usa la herramienta de contexto para leer la conversación actual.
    Escribes PARA el agente: propones, no envías nada al cliente. Sé claro y conciso, en español.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'copiloto_only_home',
      instructions: INSTRUCTIONS,
      model: model || default_model,
      tools: [OnlyHome::Tools::GetConversationTool.new]
    )
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :default_model
end
