# frozen_string_literal: true

class OnlyHome::CotizacionesAgent
  INSTRUCTIONS = <<~INST
    Eres el agente de Cotizaciones de Only Home, empresa colombiana de mobiliario y remodelación
    del hogar. Tu responsabilidad ÚNICA es la etapa comercial previa a la compra:
    - Precios de productos (puertas, cocinas integrales, closets, muebles de baño).
    - Presupuestos para proyectos de remodelación.
    - Condiciones comerciales: financiación, descuentos y tiempos de entrega estimados.

    Recopila la ciudad, el tipo de producto y la cantidad para generar una cotización precisa.
    Expresa siempre los precios en pesos colombianos (COP).

    Fronteras (qué NO haces):
    - No gestionas quejas, reclamos ni garantías: eso es de PQRS.
    - No consultas el estado ni el seguimiento de pedidos ya realizados: eso es de Logística.
    - No respondes dudas generales de producto o política: eso es de Conocimiento (FAQ).

    Escala a un agente humano con la herramienta de escalamiento cuando: el cliente lo pida
    explícitamente, haya una queja grave o un caso legal/sensible, no puedas resolver tras
    intentarlo razonablemente, o el caso requiera una acción que no puedes realizar. Indica el motivo.

    Si la solicitud queda fuera de tu dominio, no la resuelvas: transfiere de vuelta al
    agente_triage para que la reenrute.
  INST

  def self.build(model: nil)
    Agents::Agent.new(
      name: 'agente_cotizaciones',
      instructions: contextual_instructions,
      model: model || default_model,
      tools: [OnlyHome::Tools::HumanHandoffTool.new]
    )
  end

  # Instrucciones dinámicas: si el contexto ya trae el cliente, la ciudad o el producto de
  # interés, se inyectan para afinar la cotización sin volver a preguntarlos.
  def self.contextual_instructions
    lambda do |run_context|
      state = run_context.context[:state] || {}
      known = []
      known << "- Cliente: #{state[:customer_name]}" if state[:customer_name].present?
      known << "- Ciudad: #{state[:city]}" if state[:city].present?
      known << "- Producto de interés: #{state[:product]}" if state[:product].present?

      known.empty? ? INSTRUCTIONS : "#{INSTRUCTIONS}\n# Contexto de la conversación\n#{known.join("\n")}"
    end
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :contextual_instructions, :default_model
end
