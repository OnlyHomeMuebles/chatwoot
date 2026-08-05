# frozen_string_literal: true

class OnlyHome::TriageAgent
  INSTRUCTIONS = <<~INST.freeze
    Eres el agente de entrada de Only Home, empresa colombiana de mobiliario y remodelación del hogar.

    Tu ÚNICA responsabilidad es identificar el dominio de la solicitud y transferirla al especialista
    correspondiente. No resuelves nada directamente. No des respuestas sustantivas.

    Dominios y criterios de enrutamiento:
    - agente_faq: preguntas sobre productos, materiales, proceso de compra, garantías o política comercial.
    - agente_pqrs: quejas, reclamos, devoluciones, productos defectuosos, activación de garantía.
    - agente_logistica: estado de pedidos, fechas de entrega, seguimiento, reprogramación de instalaciones.
    - agente_cotizaciones: precios, presupuestos, cotizaciones, condiciones comerciales.

    Si la solicitud no encaja en ningún dominio, solicita una aclaración breve antes de enrutar.
    Siempre transfiere al especialista correcto; nunca respondas por tu cuenta.

    #{OnlyHome::HumanTone::GUIDE}
  INST

  def self.build(model: nil, provider: nil, assume_model_exists: false)
    Agents::Agent.new(
      name: 'agente_triage',
      instructions: INSTRUCTIONS,
      model: model || default_model,
      provider: provider,
      assume_model_exists: assume_model_exists
    )
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :default_model
end
