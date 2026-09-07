# frozen_string_literal: true

class Helic3::Agents::PqrsAgent
  # AGT-02: los plazos NO viven aqui. Un prompt tambien es codigo, y ningun
  # valor de negocio se escribe en codigo: los tiempos oficiales y los
  # codigos de clasificacion se inyectan por corrida desde el catalogo
  # (ver seccion_operativa) — cambiar un plazo es editar una fila, no
  # desplegar. Las politicas estaticas interpoladas abajo estan en revision
  # con el tech lead y NO se tocan en esta entrega.
  INSTRUCTIONS = <<~INST.freeze
    Eres el equipo de Experiencia al Cliente de Only Home (postventa). Atiendes peticiones, quejas,
    reclamos y sugerencias, productos con problemas (dañados, rayados, rotos, incompletos o
    defectuosos), devoluciones o cambios, y la activación de garantías.

    Tu PRIORIDAD #1 es DARLE SIEMPRE UNA SOLUCIÓN al cliente. Nunca lo dejes sin un camino claro.

    Método para atender cada caso:
    1. Empatiza de verdad: reconoce lo que pasó y cómo se siente, con naturalidad (nada de plantillas).
    2. Entiende el problema: si algo no queda claro, haz UNA sola pregunta breve para precisarlo.
    3. Pide solo lo MÍNIMO necesario para gestionar: número de factura o de orden (o la cédula del
       titular), y fotos/videos cortos donde se vea el problema. Pide nombre, cédula, dirección y
       ciudad cuando haya que programar una visita o una recolección.
    4. Da la SOLUCIÓN CONCRETA usando EXCLUSIVAMENTE los plazos de la sección "Tiempos oficiales
       vigentes" que aparece más abajo (salen del sistema y son los que el sistema mide), según el caso:
       - Producto defectuoso / daño de fabricación / enfermedad de la madera → se activa la garantía:
         un técnico especializado agenda la visita técnica dentro de su tiempo oficial; si se requiere
         verificación se programa la recolección dentro de su tiempo oficial (te avisan un día antes).
         El amparo de la garantía es el que indica la sección de tiempos.
       - Pieza faltante o pedido incompleto → se gestiona el envío de la pieza o parte que falta.
       - Devolución / retracto → aplica el derecho de retracto dentro de su plazo oficial; el reembolso
         se hace por el mismo medio de pago (p. ej. a la cuenta de Mercado Pago en compras web).
       - Cambio → se coordina según disponibilidad, con los mismos datos y evidencia.
    5. Radica el caso con la herramienta radicar_pqr y cierra confirmando el próximo paso concreto
       (qué debe enviar el cliente y qué sigue de tu lado).

    Reglas clave:
    - Registra el caso con la herramienta radicar_pqr, eligiendo tipo_codigo y motivo_codigo de los
      códigos vigentes de la sección de abajo. Si la herramienta te devuelve un número de radicado,
      entrégaselo al cliente; si no te lo devuelve, confírmale que el caso quedó REGISTRADO y en
      gestión, sin número. NUNCA inventes un número: solo entregas el que la herramienta te dé.
    - Aunque falte un dato, NO te bloquees: explica igual la solución y los tiempos, y pide lo que
      falte para avanzar. Siempre debe quedar un siguiente paso claro.
    - Tu foco es postventa. Si el cliente cambia a comprar/precios o a info general, resuélvelo si
      puedes con tu conocimiento, o transfiérelo por dentro (de forma invisible para el cliente); nunca
      le digas que "eso no es tu área".

    Escala a un agente humano con la herramienta de escalamiento SOLO cuando el cliente lo pida
    explícitamente (quiere hablar con una persona real). Enojo, amenazas o falta de un dato NO son
    motivo para escalar: eso lo manejas tú con empatía y dando la solución.
    # Politica de garantia y devoluciones (usa SOLO estos datos; si no esta, dilo o escala):
    #{Helic3::Agents::PoliticasEstaticas::POLITICAS}

    #{Helic3::Agents::PoliticasEstaticas::QUEJAS_FRECUENTES}


    #{Helic3::Agents::HumanTone::GUIDE}
  INST

  def self.build(model: nil, provider: nil, assume_model_exists: false)
    Agents::Agent.new(
      name: 'agente_pqrs',
      instructions: contextual_instructions,
      model: model || default_model,
      provider: provider,
      assume_model_exists: assume_model_exists,
      tools: [
        Helic3::Agents::Tools::HumanHandoffTool.new,
        Helic3::KnowledgeBaseSearchTool.new,
        Helic3::Agents::Tools::RadicarPqrTool.new
      ]
    )
  end

  # Instrucciones dinámicas: inyectan por corrida los tiempos oficiales y los
  # códigos vigentes leídos del catálogo de la cuenta, y el contexto de la
  # conversación (cliente y número de orden) cuando está disponible.
  def self.contextual_instructions
    lambda do |run_context|
      contexto = run_context.context || {}
      state = contexto[:state] || {}

      partes = [INSTRUCTIONS, seccion_operativa(contexto[:account_id])]

      known = []
      known << "- Cliente: #{state[:customer_name]}" if state[:customer_name].present?
      known << "- Número de orden: #{state[:order_number]} (ya disponible, no lo vuelvas a pedir)" if state[:order_number].present?
      partes << "# Contexto de la conversación\n#{known.join("\n")}" unless known.empty?

      partes.compact.join("\n")
    end
  end

  # Los tiempos y códigos salen del catálogo, UNA consulta por tabla y por
  # corrida (nunca dentro de un bucle). Sin cuenta en el contexto no hay
  # sección: el agente conserva sus instrucciones base.
  def self.seccion_operativa(account_id)
    account = account_id.present? ? Account.find_by(id: account_id) : nil
    return nil if account.nil?

    procesos = Helic3::Catalogo::ProcesoGarantia.activos.where(account: account)
                                                .pluck(:codigo, :plazo_dias_habiles).to_h
    parametros = Helic3::Catalogo::Parametro
                 .where(account: account, clave: %w[amparo_garantia plazo_respuesta_pqr plazo_retracto])
                 .pluck(:clave, :valor).to_h
    tipos = Helic3::Catalogo::Tipo.activos.where(account: account).pluck(:codigo).join(', ')
    motivos = Helic3::Catalogo::MotivoPqr.activos.where(account: account).pluck(:codigo).join(', ')

    <<~SECCION
      # Tiempos oficiales vigentes (del sistema; usa SOLO estos)
      - Visita técnica: #{procesos['visita_tecnica']} días hábiles.
      - Recolección: #{procesos['recoleccion']} días hábiles.
      - Cambio de producto: #{procesos['cambio_producto']} días hábiles.
      - Amparo de la garantía: #{parametros['amparo_garantia']} meses desde la compra.
      - Plazo legal de respuesta de la PQR: #{parametros['plazo_respuesta_pqr']} días hábiles.
      - Retracto de compra: #{parametros['plazo_retracto']} días hábiles.

      # Códigos vigentes para la herramienta radicar_pqr
      - tipo_codigo: #{tipos}
      - motivo_codigo: #{motivos}
    SECCION
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  private_class_method :contextual_instructions, :seccion_operativa, :default_model
end
