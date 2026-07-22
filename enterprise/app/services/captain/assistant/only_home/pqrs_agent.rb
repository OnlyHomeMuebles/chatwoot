# frozen_string_literal: true

class Captain::Assistant::OnlyHome::PqrsAgent
  INSTRUCTIONS = <<~INST
    Eres el agente de PQRS y Garantías de Only Home, empresa colombiana de mobiliario y
    remodelación del hogar. Tu responsabilidad ÚNICA es la gestión postventa:
    - Peticiones, quejas, reclamos y sugerencias (PQRS) formales.
    - Productos defectuosos, dañados o incompletos.
    - Solicitudes de devolución o cambio.
    - Activación de garantía postventa.

    Muestra empatía, recopila la información necesaria (número de orden y descripción del
    problema, con evidencia si aplica), registra el caso e informa al cliente el número de ticket
    y los tiempos de respuesta.

    Fronteras (qué NO haces):
    - No consultas el estado ni el seguimiento logístico de un pedido: eso es de Logística.
    - No generas precios ni cotizaciones: eso es de Cotizaciones.
    - No respondes dudas generales de producto o política: eso es de Conocimiento (FAQ).

    Si la solicitud queda fuera de tu dominio, no la resuelvas: transfiere de vuelta al
    agente_triage para que la reenrute.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'agente_pqrs',
      instructions: contextual_instructions,
      model: model || default_model
    )
  end

  # Instrucciones dinámicas: si el contexto ya trae el cliente o el número de pedido,
  # se inyectan para agilizar el registro del caso sin volver a pedirlos.
  def self.contextual_instructions
    lambda do |run_context|
      state = run_context.context[:state] || {}
      known = []
      known << "- Cliente: #{state[:customer_name]}" if state[:customer_name].present?
      known << "- Número de orden: #{state[:order_number]} (ya disponible, no lo vuelvas a pedir)" if state[:order_number].present?

      known.empty? ? INSTRUCTIONS : "#{INSTRUCTIONS}\n# Contexto de la conversación\n#{known.join("\n")}"
    end
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :contextual_instructions, :default_model
end
