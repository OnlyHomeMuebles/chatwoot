# frozen_string_literal: true

# H3A-08: arma la orquesta leyendo helic3_agentes (filtrados por bandeja y
# activos), en vez de instanciar las cinco clases a mano. Crear/editar/pausar un
# agente cambia el comportamiento en el siguiente mensaje, sin desplegar.
#
# Paridad (crit 1): con la semilla de H3A-04 (mismo prompt via PromptBuilder +
# mismas herramientas + mismas secciones contextuales por codigo) el resultado
# es el mismo de hoy.
#
# Sin agentes activos para la bandeja (crit 3): no hay runner; el job deja la
# conversacion al humano y nada se rompe (ver #hay_agentes?).
#
# El modelo/proveedor salen de LlmRuntime (decision: modelo POR CUENTA). La
# columna fila.modelo ya se respeta como override (construir_agente), asi que la
# decision "modelo por agente" solo requiere llenar esa columna desde la UI.
class Helic3::Agents::RunnerService
  # inbox/account son opcionales: sin ellos, modo :clases (comportamiento de hoy),
  # que es lo que usan los llamadores y specs previos a H3A-08.
  def initialize(inbox: nil, account: nil, model: nil, provider: nil, assume_model_exists: false)
    @inbox = inbox
    @account = account || inbox&.account
    @model = model
    @provider = provider
    @assume_model_exists = assume_model_exists
  end

  # modo activo segun la bandera por cuenta (H3A-12): :bd lee la base de datos,
  # :clases usa el comportamiento actual. Se expone para dejarlo en el log.
  def modo
    Helic3::Agents::FeatureFlag.agentes_desde_bd?(@account) ? :bd : :clases
  end

  # En modo :bd, ¿hay agentes activos para esta bandeja? Si no, el job deja la
  # conversacion al humano (crit 3 de H3A-08). En modo :clases siempre hay 5.
  def hay_agentes?
    modo == :bd ? filas.any? : true
  end

  def run(message, context: {})
    return nil if runner.nil?

    result = runner.run(message, context: context)
    registrar_ruteo(result) if modo == :bd
    result
  end

  private

  # H3A-09 crit 3: deja en el log a que agente se enruto y con que criterio. El
  # agente que atendio queda en el contexto del resultado (current_agent). Si es el
  # triage (es_sistema, sin criterio) se registra que la conversacion se quedo en
  # recepcion o se derivo a un humano.
  def registrar_ruteo(result)
    codigo = result&.context&.dig(:current_agent)
    return if codigo.blank?

    Rails.logger.info("[Helic3][ruteo] enrutó a #{codigo} · #{detalle_ruteo(codigo)}")
  rescue StandardError => e
    Rails.logger.warn("[Helic3][ruteo] no se pudo registrar el ruteo: #{e.message}")
  end

  def detalle_ruteo(codigo)
    criterio = filas.find { |f| f.codigo == codigo }&.criterio_ruteo
    criterio.present? ? "criterio: #{criterio}" : 'recepción/derivación a humano (sin criterio)'
  end

  # H3A-06: los agentes de la bandeja salen de la cache (invalidada al guardar/pausar),
  # no de la BD en cada mensaje. Memoizado ademas por corrida.
  def filas
    return [] if @inbox.nil?

    @filas ||= Helic3::Agents::ConfigCache.agentes_para(@inbox)
  end

  def runner
    return @runner if defined?(@runner)

    agentes = build_agents
    @runner = agentes.empty? ? nil : Agents::Runner.with_agents(*agentes)
  end

  # H3A-12: elige el camino segun la bandera por cuenta. Apagada (default) usa las
  # clases actuales -> comportamiento de hoy, sin riesgo. Encendida lee la BD.
  def build_agents
    modo == :bd ? construir_desde_bd : construir_desde_clases
  end

  # camino actual (clases quemadas): fallback del flag apagado. Es el build_agents
  # original de RunnerService, intacto.
  def construir_desde_clases
    opts = { model: @model, provider: @provider, assume_model_exists: @assume_model_exists }
    triage       = Helic3::Agents::TriageAgent.build(**opts)
    faq          = Helic3::Agents::FaqAgent.build(**opts)
    pqrs         = Helic3::Agents::PqrsAgent.build(**opts)
    logistica    = Helic3::Agents::LogisticaAgent.build(**opts)
    cotizaciones = Helic3::Agents::CotizacionesAgent.build(**opts)

    triage.register_handoffs(faq, pqrs, logistica, cotizaciones)
    faq.register_handoffs(triage)
    pqrs.register_handoffs(triage)
    logistica.register_handoffs(triage)
    cotizaciones.register_handoffs(triage)

    [triage, faq, pqrs, logistica, cotizaciones]
  end

  # H3A-08 (modo :bd): construye cada agente desde su fila y cablea los handoffs en
  # estrella: triage <-> cada especialista. El triage (es_sistema) va primero.
  def construir_desde_bd
    return [] if filas.empty?

    construidos = filas.index_with { |fila| construir_agente(fila) }
    triage_fila = filas.find(&:es_sistema)
    # sin triage no hay hub de ruteo (borde raro; con la semilla no ocurre)
    return construidos.values if triage_fila.nil?

    cablear_orquesta(construidos, triage_fila)
  end

  # deja el triage como entrada y con handoff a cada especialista; cada especialista
  # solo con handoff de vuelta al triage (estrella, sin bucles).
  def cablear_orquesta(construidos, triage_fila)
    triage = construidos[triage_fila]
    especialistas = construidos.except(triage_fila).values
    triage.register_handoffs(*especialistas) if especialistas.any?
    especialistas.each { |esp| esp.register_handoffs(triage) }
    [triage, *especialistas]
  end

  def construir_agente(fila)
    Agents::Agent.new(
      name: fila.codigo,
      instructions: instrucciones_para(fila),
      # N1 (revision de Jhan): mismo fallback que las clases (model || default_model),
      # para que los dos caminos coincidan cuando el llamador no pasa modelo. La
      # columna fila.modelo queda lista para la decision "modelo por agente".
      model: fila.modelo.presence || @model || default_model,
      provider: @provider,
      assume_model_exists: @assume_model_exists,
      # H3A-10: solo las herramientas de la columna + derivar_humano (siempre)
      tools: Helic3::Agents::CatalogoHerramientas.instanciar(fila.herramientas)
    )
  end

  # mismo default que las clases (TriageAgent.default_model, etc.): el modelo de
  # OpenAI configurable desde Super Admin, o la constante del proyecto.
  def default_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end

  # cuerpo estatico (PromptBuilder, H3A-07) + secciones contextuales por corrida.
  # Las contextuales viven en codigo keyed por codigo: reproducen exactamente lo
  # que hoy hacen las clases (consentimiento del triage, tiempos/codigos de PQRS,
  # contexto de conversacion de logistica/cotizaciones).
  def instrucciones_para(fila)
    base = Helic3::Agents::PromptBuilder.new(fila)
    # el triage se identifica por es_sistema (no por codigo), para que siga siendo
    # el enrutador aunque el admin lo renombre.
    return instrucciones_triage(fila) if fila.es_sistema

    case fila.codigo
    when 'agente_pqrs' then instrucciones_pqrs(base)
    when 'agente_logistica'
      instrucciones_con_contexto(base, [[:customer_name, 'Cliente'], [:order_number, 'Número de pedido']])
    when 'agente_cotizaciones'
      instrucciones_con_contexto(base, [[:customer_name, 'Cliente'], [:city, 'Ciudad'], [:product, 'Producto de interés']])
    else
      base.construir # estatico: FAQ y agentes nuevos creados por el admin
    end
  end

  # triage: (H3A-09) reemplaza el directorio de ruteo estatico por uno armado con
  # los criterio_ruteo de los especialistas activos de la bandeja, y antepone el
  # consentimiento AGT-07 (reutiliza la logica de TriageAgent).
  def instrucciones_triage(fila)
    base = Helic3::Agents::PromptBuilder.new(fila)
    lambda do |run_context|
      contexto = run_context.context || {}
      state = contexto[:state] || {}
      # (revision Jhan) especialistas se resuelve DENTRO del lambda (por corrida), no al
      # construir: asi refleja los agentes activos aunque la instancia se cacheara a futuro.
      # fila.prompt.to_s evita el NoMethodError si un admin dejo el prompt en nil.
      especialistas = filas.reject(&:es_sistema)
      cuerpo = Helic3::Agents::TriageAgent.con_directorio_dinamico(fila.prompt.to_s, especialistas)
      [base.construir(cuerpo: cuerpo),
       Helic3::Agents::TriageAgent.seccion_apertura(contexto[:account_id], state[:consentimiento_datos_at])]
        .compact.join("\n\n")
    end
  end

  # pqrs: tiempos y codigos del catalogo (reutiliza PqrsAgent) + contexto conocido
  def instrucciones_pqrs(base)
    lambda do |run_context|
      contexto = run_context.context || {}
      state = contexto[:state] || {}
      known = []
      known << "- Cliente: #{state[:customer_name]}" if state[:customer_name].present?
      known << "- Número de orden: #{state[:order_number]} (ya disponible, no lo vuelvas a pedir)" if state[:order_number].present?
      partes = [base.construir, Helic3::Agents::PqrsAgent.seccion_operativa(contexto[:account_id])]
      partes << "# Contexto de la conversación\n#{known.join("\n")}" unless known.empty?
      partes.compact.join("\n")
    end
  end

  # logistica/cotizaciones: solo el contexto de la conversacion si viene en el state
  def instrucciones_con_contexto(base, campos)
    lambda do |run_context|
      state = (run_context.context || {})[:state] || {}
      known = campos.filter_map { |clave, etiqueta| "- #{etiqueta}: #{state[clave]}" if state[clave].present? }
      known.empty? ? base.construir : "#{base.construir}\n# Contexto de la conversación\n#{known.join("\n")}"
    end
  end
end
