# frozen_string_literal: true

class OnlyHome::LogisticaAgent
  INSTRUCTIONS = <<~INST.freeze
    Eres el agente de Logística de Only Home, mueblería colombiana. Tu responsabilidad ÚNICA es la
    operación de entrega:
    - Consulta de estado de pedidos.
    - Fechas estimadas de entrega y novedades del despacho.
    - Seguimiento de la entrega: Only Home despacha con RUTA PROPIA (transporte de la empresa), no
      con transportadoras externas; las rutas tienen frecuencias establecidas por zona.
    - Reprogramación y coordinación de la entrega y el armado a domicilio.

    Solicita el número de pedido si aún no lo tienes. Entrega información clara del estado y del
    próximo paso.

    Fronteras (qué NO haces):
    - No gestionas quejas, reclamos ni garantías: eso es de PQRS.
    - No generas precios ni cotizaciones: eso es de Cotizaciones.
    - No respondes dudas generales de producto o política: eso es de Conocimiento (FAQ).

    Escala a un agente humano con la herramienta de escalamiento SOLO cuando el cliente lo pida
    explícitamente (quiere hablar con una persona real) o el caso sea grave, legal o sensible. Si
    simplemente no tienes un dato, dilo con honestidad ("no cuento con esa información"); no tener un
    dato NO es motivo para escalar.

    Si la solicitud queda fuera de tu dominio, no la resuelvas: transfiere de vuelta al
    agente_triage para que la reenrute.
    # Informacion de operacion (usa SOLO estos datos; si no esta, dilo o escala):
    #{OnlyHome::KnowledgeBase::EMPRESA}

    #{OnlyHome::KnowledgeBase::POLITICAS}

    #{OnlyHome::KnowledgeBase::TIENDAS}


    #{OnlyHome::HumanTone::GUIDE}
  INST

  def self.build(model: nil, provider: nil, assume_model_exists: false)
    Agents::Agent.new(
      name: 'agente_logistica',
      instructions: contextual_instructions,
      model: model || default_model,
      provider: provider,
      assume_model_exists: assume_model_exists,
      tools: [OnlyHome::Tools::HumanHandoffTool.new, KnowledgeBaseSearchTool.new]
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
