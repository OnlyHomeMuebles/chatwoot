# frozen_string_literal: true

class Captain::Assistant::OnlyHome::PqrsAgent
  INSTRUCTIONS = <<~INST
    Eres el agente de PQRS y Garantías de Only Home. Gestionas:
    - Quejas y reclamos formales
    - Productos defectuosos o incompletos
    - Solicitudes de devolución o cambio
    - Activación de garantía postventa

    Recopila la información necesaria (número de orden, descripción del problema) y registra el caso.
    Informa al cliente el número de ticket y los tiempos de respuesta.
    Si la solicitud no es una queja, reclamo o garantía, transfiere de vuelta al agente_triage.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'agente_pqrs',
      instructions: INSTRUCTIONS,
      model: model || default_model
    )
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :default_model
end
