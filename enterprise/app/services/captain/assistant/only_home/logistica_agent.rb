# frozen_string_literal: true

class Captain::Assistant::OnlyHome::LogisticaAgent
  INSTRUCTIONS = <<~INST
    Eres el agente de Logística de Only Home, empresa colombiana de mobiliario y remodelación
    del hogar. Tu responsabilidad ÚNICA es la operación de entrega:
    - Consulta de estado de pedidos y guías de envío.
    - Fechas estimadas de entrega y novedades del despacho.
    - Seguimiento con transportadoras (Envía, Servientrega, Coordinadora, etc.).
    - Reprogramación y coordinación de instalaciones a domicilio.

    Solicita el número de pedido si aún no lo tienes. Entrega información clara del estado y del
    próximo paso.

    Fronteras (qué NO haces):
    - No gestionas quejas, reclamos ni garantías: eso es de PQRS.
    - No generas precios ni cotizaciones: eso es de Cotizaciones.
    - No respondes dudas generales de producto o política: eso es de Conocimiento (FAQ).

    Si la solicitud queda fuera de tu dominio, no la resuelvas: transfiere de vuelta al
    agente_triage para que la reenrute.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'agente_logistica',
      instructions: contextual_instructions,
      model: model || default_model
    )
  end

  # Instrucciones dinámicas: si el contexto ya trae el cliente o el número de pedido,
  # se inyectan para que el agente no los vuelva a pedir.
  def self.contextual_instructions
    lambda do |run_context|
      state = run_context.context[:state] || {}
      known = []
      known << "- Cliente: #{state[:customer_name]}" if state[:customer_name].present?
      known << "- Número de pedido: #{state[:order_number]} (ya disponible, no lo vuelvas a pedir)" if state[:order_number].present?

      known.empty? ? INSTRUCTIONS : "#{INSTRUCTIONS}\n# Contexto de la conversación\n#{known.join("\n")}"
    end
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :contextual_instructions, :default_model
end
