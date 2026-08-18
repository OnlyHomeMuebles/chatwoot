# frozen_string_literal: true

# Agente único de Only Home para el modo RAG (open source local). En vez de enrutar entre varios
# agentes (que los modelos locales pequeños no hacen bien), un solo agente atiende todo y recibe,
# inyectados en el contexto, SOLO los fragmentos de conocimiento relevantes que recuperó el RAG.
# Así un modelo local pequeño (p. ej. qwen2.5:7b) responde con precisión y sin inventar.
class OnlyHome::SoloAgent
  INSTRUCTIONS = <<~INST.freeze
    Eres el asesor virtual de Only Home, mueblería colombiana. Atiendes al cliente de punta a punta:
    productos y precios, cotizaciones, tiendas y horarios, envíos, estado de pedidos, garantías y
    quejas. Responde en español, con calidez y de forma concreta.

    REGLAS ESTRICTAS (obligatorias):
    - Usa ÚNICAMENTE la INFORMACIÓN RELEVANTE que aparece abajo. Está PROHIBIDO inventar o suponer
      precios, direcciones, teléfonos, ciudades o características.
    - Si te preguntan por una ciudad, responde solo con tiendas que estén explícitamente EN esa
      ciudad; si no hay ninguna en la información, dilo con honestidad. Nunca presentes una tienda de
      otra ciudad como si fuera de la ciudad preguntada.
    - Si un dato no está en la información de abajo, di con honestidad que no lo tienes y ofrece pasar
      con un asesor humano. No lo inventes ni lo deduzcas.
    - Los precios son de referencia (COP); pueden variar por acabado, disponibilidad y vigencia.

    Escala a un agente humano con la herramienta de escalamiento cuando: el cliente lo pida, haya una
    queja grave o un caso legal/sensible, o no puedas resolver tras intentarlo.

    #{OnlyHome::HumanTone::GUIDE}
  INST

  def self.build(model: nil, provider: nil, assume_model_exists: false)
    Agents::Agent.new(
      name: 'asesor_only_home',
      instructions: contextual_instructions,
      model: model || default_model,
      provider: provider,
      assume_model_exists: assume_model_exists,
      temperature: 0,
      tools: [OnlyHome::Tools::HumanHandoffTool.new]
    )
  end

  # Inyecta los fragmentos que el RAG recuperó y dejó en el contexto (state[:knowledge]).
  def self.contextual_instructions
    lambda do |run_context|
      state = run_context.context[:state] || {}
      knowledge = state[:knowledge].presence ||
                  'No se recuperó información específica para esta consulta; ofrece pasar con un asesor humano.'
      "#{INSTRUCTIONS}\n# INFORMACIÓN RELEVANTE DE ONLY HOME (usa SOLO esto):\n#{knowledge}"
    end
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :contextual_instructions, :default_model
end
