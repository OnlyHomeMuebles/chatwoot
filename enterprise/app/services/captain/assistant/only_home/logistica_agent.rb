# frozen_string_literal: true

class Captain::Assistant::OnlyHome::LogisticaAgent
  INSTRUCTIONS = <<~INST
    Eres el agente de Logística de Only Home. Gestionas:
    - Consulta de estado de pedidos y guías de envío
    - Fechas estimadas de entrega
    - Seguimiento con transportadoras (Envía, Servientrega, etc.)
    - Reprogramación de instalaciones a domicilio

    Solicita el número de pedido si el cliente no lo proporciona.
    Si la solicitud no es logística, transfiere de vuelta al agente_triage.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'agente_logistica',
      instructions: INSTRUCTIONS,
      model: model || default_model
    )
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :default_model
end
