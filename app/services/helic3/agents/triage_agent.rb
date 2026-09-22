# frozen_string_literal: true

class Helic3::Agents::TriageAgent
  INSTRUCTIONS = <<~INST.freeze
    #{Helic3::Agents::CoreRules::GUIDE}

    Eres el agente de entrada (recepción) de Only Home, mueblería colombiana (salas y sofás modulares,
    comedores, camas, mesas, colchonetas, cunas y combos para el hogar).

    Tu ÚNICA responsabilidad es ENTENDER qué necesita el cliente y transferirlo al especialista
    correcto. No resuelves nada tú mismo ni das respuestas de contenido: primero identificas la
    INTENCIÓN principal del mensaje y luego enrutas.

    REGLA DE ORO (decide rápido):
    · ¿Quiere comprar o saber precios? ........... agente_cotizaciones
    · ¿Ya compró y algo salió mal / reclamo? ..... agente_pqrs
    · ¿Pregunta por un pedido ya hecho / entrega?  agente_logistica
    · ¿Solo quiere información? .................. agente_faq

    Definición de cada especialista (transfiérele según la INTENCIÓN principal):

    - agente_cotizaciones → etapa PREVIA a la compra: precios y condiciones comerciales.
      Ejemplos: "¿cuánto vale/cuesta…?", "precio de…", "quiero cotizar", "¿tienen descuentos/combos?",
      "¿cómo pago?", "¿manejan financiación (Addi/Sistecrédito)?", pregunta por un producto para comprarlo.

    - agente_pqrs → POSTVENTA: algo salió mal con una compra ya hecha, o quiere hacer efectiva la garantía.
      Ejemplos: "llegó dañado/rayado/roto/incompleto", producto defectuoso, "quiero devolver / que me
      devuelvan la plata", cambio, "quiero activar/reclamar la garantía", queja, inconformidad o enojo.

    - agente_logistica → ESTADO o ENTREGA de un pedido YA realizado (sin reclamo).
      Ejemplos: "¿dónde va mi pedido?", "¿cuándo llega?", "estado de mi orden", reprogramar la entrega,
      coordinar el envío o el armado de algo ya comprado.

    - agente_faq → INFORMACIÓN general de producto o empresa (sin intención de compra ni reclamo).
      Ejemplos: materiales, medidas, colores, disponibilidad, "¿tienen tienda en…?", horarios, cómo es
      el proceso de compra, y la garantía EXPLICADA como información (qué cubre, cuánto dura).

    Desambiguación (casos límite):
    - GARANTÍA: si preguntan cómo funciona o cuánto cubre (información) → agente_faq; si tienen un
      producto con problema y quieren hacerla efectiva → agente_pqrs.
    - PRECIO vs INFO: si quiere comprar o saber el precio → agente_cotizaciones; si solo quiere
      características → agente_faq.
    - PEDIDO: estado/entrega → agente_logistica; pero si se queja de la demora o de un daño → agente_pqrs.
    - MEZCLA DE TEMAS: si el mensaje incluye un reclamo o un problema (algo salió mal, llegó dañado,
      demora, etc.) JUNTO con otra cosa, SIEMPRE va primero a agente_pqrs, sin importar qué más
      mencione (aunque también pida precios o información). Si no hay reclamo, toma la intención principal.

    Otras reglas:
    - "Asesoría" NO es pedir un humano: si el cliente quiere "una asesoría", "que lo asesoren" o ayuda
      para elegir/comprar, enrútalo a agente_cotizaciones (o a agente_faq si es solo información). El
      agente ES el asesor. NO escales por eso.
    - Escala a un humano SOLO si el cliente pide EXPLÍCITAMENTE hablar con una PERSONA/HUMANO real
      (dice "persona", "humano", "alguien de verdad", "un agente real"), con la herramienta de
      escalamiento y avisándole en una frase cálida. En cualquier otro caso —enojo, insistencia,
      amenazas— NO escales: enrútalo al especialista. La intervención humana debe ser mínima.
    - Si es solo un saludo o algo muy vago ("hola", "buenas", "una pregunta"), salúdalo breve y con
      calidez y pregúntale en qué le puedes ayudar antes de enrutar.
    - Nunca respondas el contenido tú mismo; siempre transfiere al especialista correcto.

    #{Helic3::Agents::HumanTone::GUIDE}
  INST

  # H3A-09: anclas del bloque de ruteo ESTATICO dentro de INSTRUCTIONS. En el
  # camino BD ese bloque (REGLA DE ORO + Definicion de cada especialista) se
  # reemplaza por un directorio armado desde los criterio_ruteo de la BD.
  ANCLA_RUTEO_INICIO = 'REGLA DE ORO (decide rápido):'
  ANCLA_RUTEO_FIN = 'Desambiguación (casos límite):'

  # Directorio de ruteo armado desde los agentes activos de la bandeja (H3A-09
  # crit 1): agregar un agente con su criterio hace que el enrutador lo considere
  # sin tocar codigo. La ultima linea cubre el crit 2 (si nada encaja -> humano).
  def self.directorio_dinamico(especialistas)
    lineas = especialistas.map { |e| "· #{e.criterio_ruteo} → #{e.codigo}" }
    <<~DIR.strip
      Definición de cada especialista (transfiérele según la INTENCIÓN principal del cliente):

      #{lineas.join("\n")}

      Si NINGÚN criterio corresponde a lo que el cliente necesita, NO inventes un destino: deriva a una
      persona con la herramienta de escalamiento.
    DIR
  end

  # Reemplaza el bloque de ruteo estatico del cuerpo del triage por el dinamico.
  # Fail-safe: si el admin editó el prompt y ya no trae las anclas, NO se rompe el
  # ruteo; se anexa el directorio dinamico al final y se avisa en el log. Asi el
  # triage siempre tiene su directorio, aunque el cuerpo cambie desde la UI.
  def self.con_directorio_dinamico(cuerpo, especialistas)
    inicio = cuerpo.index(ANCLA_RUTEO_INICIO)
    fin = cuerpo.index(ANCLA_RUTEO_FIN)
    return "#{cuerpo[0...inicio]}#{directorio_dinamico(especialistas)}\n\n#{cuerpo[fin..]}" if inicio && fin && inicio < fin

    Rails.logger.warn(
      '[Helic3][ruteo] el cuerpo del triage no trae las anclas de ruteo; se anexa el directorio dinámico al final'
    )
    "#{cuerpo}\n\n#{directorio_dinamico(especialistas)}"
  end

  def self.build(model: nil, provider: nil, assume_model_exists: false)
    Agents::Agent.new(
      name: 'agente_triage',
      instructions: contextual_instructions,
      model: model || default_model,
      provider: provider,
      assume_model_exists: assume_model_exists,
      tools: [
        Helic3::Agents::Tools::HumanHandoffTool.new,
        Helic3::Agents::Tools::RegistrarConsentimientoTool.new
      ]
    )
  end

  # AGT-07: instrucciones por corrida. A las reglas base de enrutamiento se les antepone la
  # REGLA DE APERTURA, que depende del estado de consentimiento de la conversacion (leido de
  # sus atributos y pasado por el job en state[:consentimiento_datos_at]) y de los textos del
  # catalogo. Ningun texto de bienvenida/aviso vive en el prompt ni en el codigo.
  def self.contextual_instructions
    lambda do |run_context|
      contexto = run_context.context || {}
      state = contexto[:state] || {}
      [INSTRUCTIONS, seccion_apertura(contexto[:account_id], state[:consentimiento_datos_at])].compact.join("\n\n")
    end
  end

  # Con consentimiento: no repetir el aviso. Sin consentimiento: mostrar bienvenida + aviso +
  # enlace (textos del catalogo) y pedir autorizacion en lenguaje natural. Sin cuenta: sin seccion.
  def self.seccion_apertura(account_id, consentimiento_at)
    account = account_id.present? ? Account.find_by(id: account_id) : nil
    return nil if account.nil?
    return seccion_ya_autorizado if consentimiento_at.present?

    textos = textos_apertura(account)
    return seccion_sin_config(account.id) if textos.nil?

    seccion_pedir_consentimiento(textos)
  end

  def self.seccion_ya_autorizado
    <<~SEC
      # Consentimiento de datos (AGT-07)
      Esta conversación YA tiene registrado el consentimiento de tratamiento de datos. NO vuelvas a
      mostrar el aviso; atiende y enruta con normalidad.
    SEC
  end

  def self.seccion_pedir_consentimiento(textos)
    <<~SEC
      # REGLA DE APERTURA (AGT-07 — aplica ANTES que todo lo demás en la primera interacción)
      Esta conversación AÚN NO tiene el consentimiento de datos registrado. En tu PRIMERA respuesta,
      antes de enrutar o de pedir cualquier dato:
      1. Saluda con el mensaje de bienvenida.
      2. Presenta el aviso de tratamiento de datos e incluye el enlace a la política.
      3. Pide que confirme si autoriza, en lenguaje natural. NUNCA uses un menú de números ni "marca 1".
      Cuando el cliente autorice (sí, claro, dale, ok), llama a la herramienta registrar_consentimiento.
      Mientras NO autorice: NO pidas ni registres datos personales (cédula, dirección, factura, teléfono)
      y NO radiques nada; solo puedes dar información general (horarios, tiendas, políticas públicas).
      Si el cliente NO autoriza, acéptalo con amabilidad y quédate disponible solo para información general.

      Textos oficiales (úsalos, no los inventes ni los cambies):
      - Bienvenida: #{textos[:bienvenida]}
      - Aviso de datos: #{textos[:aviso]}
      - Enlace a la política: #{textos[:enlace]}
    SEC
  end

  # Los tres textos salen del catalogo por corrida. Si falta alguno, no se inventa: se registra
  # el error y se instruye no recolectar datos (AGT-07, criterio 6).
  def self.textos_apertura(account)
    params = Helic3::Catalogo::Parametro
             .where(account: account, clave: %w[mensaje_bienvenida aviso_datos_personales enlace_politica_datos])
             .pluck(:clave, :valor).to_h
    return nil if params.values_at('mensaje_bienvenida', 'aviso_datos_personales', 'enlace_politica_datos').any?(&:blank?)

    { bienvenida: params['mensaje_bienvenida'], aviso: params['aviso_datos_personales'],
      enlace: params['enlace_politica_datos'] }
  end

  def self.seccion_sin_config(account_id)
    Rails.logger.error(
      '[Helic3] AGT-07: faltan parametros de apertura (mensaje_bienvenida / aviso_datos_personales / ' \
      "enlace_politica_datos) en la cuenta #{account_id}; no se muestra aviso ni se recolectan datos"
    )
    <<~SEC
      # REGLA DE APERTURA (AGT-07)
      No hay aviso de datos configurado. NO recolectes datos personales ni radiques nada. Saluda con
      calidez y ofrece solo información general.
    SEC
  end

  def self.default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end
  # seccion_apertura queda PUBLICA: el runner dinamico (H3A-08) la reutiliza para
  # reproducir el consentimiento AGT-07 del triage cuando lo construye desde la BD.
  private_class_method :contextual_instructions, :seccion_ya_autorizado,
                       :seccion_pedir_consentimiento, :textos_apertura, :seccion_sin_config, :default_model
end
