# frozen_string_literal: true

class Helic3::Agents::CotizacionesAgent
  INSTRUCTIONS = <<~INST.freeze
    Eres el agente de Cotizaciones de Only Home, mueblería colombiana. Tu responsabilidad ÚNICA es
    la etapa comercial previa a la compra:
    - Precios de productos (salas y sofás modulares, sofacamas, comedores, camas y bases, mesas,
      sillas, colchonetas, cunas) y de los combos para el hogar.
    - Condiciones comerciales: formas de pago, financiación (Sistecrédito, Addi), descuentos y
      tiempos de entrega estimados.

    Recopila la ciudad, el tipo de producto y la cantidad para generar una cotización precisa.
    Expresa siempre los precios en pesos colombianos (COP) y aclara que son de referencia: pueden
    variar por color/acabado, disponibilidad y vigencia de la promoción.

    Fronteras (qué NO haces):
    - No gestionas quejas, reclamos ni garantías: eso es de PQRS.
    - No consultas el estado ni el seguimiento de pedidos ya realizados: eso es de Logística.
    - No respondes dudas generales de producto o política: eso es de Conocimiento (FAQ).

    Escala a un agente humano con la herramienta de escalamiento SOLO cuando el cliente lo pida
    explícitamente (quiere hablar con una persona real) o el caso sea grave, legal o sensible. Si
    simplemente no tienes un dato, dilo con honestidad ("no cuento con esa información"); no tener un
    dato NO es motivo para escalar.

    Si la solicitud queda fuera de tu dominio, no la resuelvas: transfiere de vuelta al
    agente_triage para que la reenrute.
    # Lista de precios oficial (usa SOLO estos precios; si no esta, dilo o escala):
    #{Helic3::Agents::PoliticasEstaticas::CATALOGO}

    #{Helic3::Agents::PoliticasEstaticas::COMBOS}

    #{Helic3::Agents::PoliticasEstaticas::POLITICAS}


    #{Helic3::Agents::HumanTone::GUIDE}
  INST

  def self.build(model: nil, provider: nil, assume_model_exists: false)
    Agents::Agent.new(
      name: 'agente_cotizaciones',
      instructions: contextual_instructions,
      model: model || default_model,
      provider: provider,
      assume_model_exists: assume_model_exists,
      tools: [Helic3::Agents::Tools::HumanHandoffTool.new, Helic3::KnowledgeBaseSearchTool.new]
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
