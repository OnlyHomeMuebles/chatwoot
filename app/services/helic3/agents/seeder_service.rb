# frozen_string_literal: true

# H3A-04: siembra los cinco agentes actuales como filas de helic3_agentes, para
# que el runner (H3A-08) los construya desde la BD con el MISMO comportamiento
# de hoy. Idempotente, igual que Helic3::Catalogo::SeederService: la llave
# natural es (account, codigo); si la fila ya existe, no la toca.
#
# Decision B (aprobada): el `prompt` guardado es solo el CUERPO de dominio del
# agente. Las reglas duras (CoreRules) y el tono (HumanTone) NO se guardan: los
# vuelve a anteponer el PromptBuilder (H3A-07), de modo que el prompt ensamblado
# queda idéntico y el comportamiento no cambia (criterio 4). Por eso NO se cumple
# el criterio 2 al pie de la letra ("idéntico carácter por carácter"): es la
# consecuencia directa de la decision B, hablada con Jhan.
#
# El cuerpo se EXTRAE de la clase en tiempo de siembra (no se re-escribe a mano),
# quitando el prefijo de CoreRules y el sufijo de HumanTone. Asi queda en sync
# con la clase mientras exista.
#
# OJO (paridad): las secciones CONTEXTUALES por corrida (consentimiento AGT-07
# del triage, tiempos/codigos del catalogo de PQRS, contexto de conversacion de
# logistica/cotizaciones) NO viven en el prompt: las reproduce el runner (H3A-08)
# keyed por codigo. La semilla solo trae el cuerpo estatico + los metadatos.
class Helic3::Agents::SeederService
  # codigo, clase (fuente del cuerpo), nombre visible, criterio de ruteo (lo que
  # el triage usa para decidir), herramientas del catalogo (sin derivar_humano,
  # que se inyecta siempre), y si es de sistema (el triage, no eliminable).
  AGENTES = [
    { codigo: 'agente_triage', clase: 'Helic3::Agents::TriageAgent',
      nombre: 'Recepción (Triage)', es_sistema: true, criterio_ruteo: nil,
      herramientas: %w[registrar_consentimiento] },
    { codigo: 'agente_faq', clase: 'Helic3::Agents::FaqAgent',
      nombre: 'Preguntas frecuentes (FAQ)', es_sistema: false,
      criterio_ruteo: 'Información general de producto o empresa, sin intención de compra ni reclamo: ' \
                      'materiales, medidas, colores, disponibilidad, tiendas, horarios, proceso de compra, ' \
                      'y la garantía explicada como información (qué cubre, cuánto dura).',
      herramientas: %w[buscar_conocimiento] },
    { codigo: 'agente_pqrs', clase: 'Helic3::Agents::PqrsAgent',
      nombre: 'PQR y garantías', es_sistema: false,
      criterio_ruteo: 'Postventa: algo salió mal con una compra ya hecha (llegó dañado, rayado, roto, ' \
                      'incompleto o defectuoso), devoluciones o cambios, o hacer efectiva la garantía; ' \
                      'quejas, reclamos e inconformidad. Si el mensaje incluye un reclamo, va aquí primero.',
      herramientas: %w[buscar_conocimiento radicar_pqr resolver_pqr] },
    { codigo: 'agente_logistica', clase: 'Helic3::Agents::LogisticaAgent',
      nombre: 'Logística', es_sistema: false,
      criterio_ruteo: 'Estado o entrega de un pedido YA realizado, sin reclamo: dónde va mi pedido, ' \
                      'cuándo llega, reprogramar la entrega, coordinar el envío o el armado.',
      herramientas: %w[buscar_conocimiento] },
    { codigo: 'agente_cotizaciones', clase: 'Helic3::Agents::CotizacionesAgent',
      nombre: 'Cotizaciones', es_sistema: false,
      criterio_ruteo: 'Etapa previa a la compra: precios y condiciones comerciales, cotizar, descuentos, ' \
                      'combos, formas de pago y financiación (Addi, Sistecrédito).',
      herramientas: %w[buscar_conocimiento] }
  ].freeze

  def initialize(account)
    @account = account
  end

  def sembrar!
    AGENTES.each do |defn|
      next if Helic3::Agente.exists?(account: @account, codigo: defn[:codigo])

      Helic3::Agente.create!(
        account: @account,
        codigo: defn[:codigo],
        nombre: defn[:nombre],
        criterio_ruteo: defn[:criterio_ruteo],
        prompt: extraer_cuerpo(defn[:clase].constantize::INSTRUCTIONS),
        herramientas: defn[:herramientas],
        es_sistema: defn[:es_sistema],
        activo: true
      )
    end
    asignar_bandejas!
    resumen
  end

  private

  # Paridad (crit 1 de H3A-08): hoy el bot corre en los inbox donde esta conectado
  # el Agent Bot de Helic3. Para que el runner filtrado por bandeja se comporte
  # igual, se vinculan los agentes a ESOS mismos inbox. Idempotente. Si no hay un
  # bot de helic3 conectado, no se asigna nada (el admin lo hara desde la UI, o el
  # runner dejara la conversacion al humano — crit 3).
  def asignar_bandejas!
    inboxes = inboxes_del_bot_helic3
    return if inboxes.empty?

    Helic3::Agente.where(account: @account, activo: true).find_each do |agente|
      inboxes.each do |inbox|
        next if Helic3::AgenteBandeja.exists?(agente_id: agente.id, inbox_id: inbox.id)

        Helic3::AgenteBandeja.create!(agente: agente, inbox: inbox)
      end
    end
  end

  # inbox de la cuenta cuyo Agent Bot apunta al webhook de helic3
  def inboxes_del_bot_helic3
    bot_ids = AgentBot.where('outgoing_url ILIKE ?', '%helic3%').pluck(:id)
    return [] if bot_ids.empty?

    @account.inboxes.joins(:agent_bot_inbox)
            .where(agent_bot_inboxes: { agent_bot_id: bot_ids }).distinct.to_a
  end

  # cuerpo de dominio: INSTRUCTIONS sin el prefijo CoreRules ni el sufijo HumanTone
  def extraer_cuerpo(instrucciones)
    core = Helic3::Agents::CoreRules::GUIDE
    tono = Helic3::Agents::HumanTone::GUIDE
    instrucciones
      .sub(/\A#{Regexp.escape(core)}\s*/m, '')
      .sub(/\s*#{Regexp.escape(tono)}\s*\z/m, '')
      .strip
  end

  def resumen
    { agentes: Helic3::Agente.where(account: @account).count,
      de_sistema: Helic3::Agente.where(account: @account, es_sistema: true).count,
      bandejas: Helic3::AgenteBandeja.where(agente_id: Helic3::Agente.where(account: @account).select(:id)).count }
  end
end
