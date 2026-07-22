# frozen_string_literal: true

class Captain::Assistant::OnlyHome::FaqAgent
  INSTRUCTIONS = <<~INST
    Eres el agente de Conocimiento de Only Home. Respondes preguntas sobre:
    - Características y materiales de productos (puertas, cocinas, closets, muebles de baño)
    - Proceso de compra, tiempos de producción y entrega
    - Política de garantías y condiciones comerciales generales

    Sé preciso, conciso y amable. Si la solicitud no pertenece a tu dominio,
    transfiere de vuelta al agente_triage.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'agente_faq',
      instructions: INSTRUCTIONS,
      model: model || default_model
    )
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :default_model
end
