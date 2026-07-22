# frozen_string_literal: true

class Captain::Assistant::OnlyHome::CotizacionesAgent
  INSTRUCTIONS = <<~INST
    Eres el agente de Cotizaciones de Only Home. Gestionas:
    - Precios de productos (puertas, cocinas, closets, muebles de baño)
    - Presupuestos para proyectos de remodelación
    - Condiciones comerciales: financiación, descuentos, tiempos de entrega estimados

    Recopila la ciudad, el tipo de producto y la cantidad para generar una cotización precisa.
    Expresa los precios en COP. Si la solicitud no es comercial, transfiere al agente_triage.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'agente_cotizaciones',
      instructions: INSTRUCTIONS,
      model: model || default_model
    )
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :default_model
end
