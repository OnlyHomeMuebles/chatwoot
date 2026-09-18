# frozen_string_literal: true

# AGT-03: la herramienta con la que el agente RESUELVE un expediente (registra el
# resultado y, si corresponde, abre la garantia). No contiene logica de dominio
# (un servicio, dos consumidores: la logica vive en Helic3::Casos::Resolver, la
# misma del panel). Esta tool solo TRADUCE entre el mundo del modelo (codigos y
# texto) y el dominio: resuelve codigos contra el catalogo, convierte errores en
# texto reutilizable, deja la nota privada y aplica la politica de autonomia.
class Helic3::Agents::Tools::ResolverPqrTool < Helic3::Agents::Tools::BaseTool
  PARAMETRO_AUTONOMIA = 'autonomia_resolver_pqr'

  description 'Resuelve el expediente PQR del cliente: registra el resultado y, si el resultado abre ' \
              'garantia, radica la garantia con su ciudad y productos. Usala cuando ya tengas claro el ' \
              'desenlace del caso. Para resultados que requieren aprobacion humana, la tool NO cierra: ' \
              'deja la propuesta para que una persona la apruebe.'

  # Los codigos validos (resultado, ciudad, motivo de garantia, detalle) los trae
  # la seccion "Codigos vigentes" del prompt, leida del catalogo de la cuenta: NO
  # se nombran aqui para no clavar un valor de negocio en el codigo. Ante un codigo
  # invalido, la tool responde la lista vigente para reintentar en la misma corrida.
  param :ticket_display_id, type: 'string',
                            desc: 'Numero del expediente PQR a resolver (el que se radico antes).'
  param :resultado_codigo, type: 'string',
                           desc: 'Codigo del resultado, de la lista vigente del sistema. Ante un codigo ' \
                                 'invalido, responde la lista vigente.'
  # solo para el caso de garantia; opcionales para el resto de resultados
  param :ciudad_codigo, type: 'string', required: false,
                        desc: 'Codigo de la ciudad de cobertura; OBLIGATORIO si el resultado abre garantia.'
  param :producto_nombre, type: 'string', required: false,
                          desc: 'Nombre del producto en garantia; obligatorio si el resultado abre garantia.'
  param :producto_referencia, type: 'string', required: false,
                              desc: 'Referencia o codigo del producto, si el cliente la da (texto libre).'
  param :motivo_garantia_codigo, type: 'string', required: false,
                                 desc: 'Codigo del motivo de garantia que clasifica el caso, de la lista vigente.'
  param :detalle_tipificado_codigo, type: 'string', required: false,
                                    desc: 'Codigo del detalle tipificado (el defecto), de la lista vigente.'

  # rubocop:disable Metrics/ParameterLists
  def perform(tool_context, ticket_display_id:, resultado_codigo:, ciudad_codigo: nil,
              producto_nombre: nil, producto_referencia: nil,
              motivo_garantia_codigo: nil, detalle_tipificado_codigo: nil)
    account = resolve_account(tool_context)
    return 'No hay una cuenta configurada para resolver.' if account.blank?

    ticket = account.tickets.find_by(display_id: ticket_display_id)
    return "No existe el expediente ##{ticket_display_id} en esta cuenta." if ticket.nil?

    resultado = Helic3::Catalogo::Resultado.activos.find_by(account: account, codigo: resultado_codigo)
    return resultados_invalidos(account) if resultado.nil?

    # construir_garantia devuelve el bloque de garantia, nil si el resultado no la
    # abre, o un String de recuperacion si un codigo de garantia es invalido.
    codigos = { ciudad_codigo: ciudad_codigo, producto_nombre: producto_nombre,
                producto_referencia: producto_referencia, motivo_garantia_codigo: motivo_garantia_codigo,
                detalle_tipificado_codigo: detalle_tipificado_codigo }
    garantia = construir_garantia(account, resultado, codigos)
    return garantia if garantia.is_a?(String)

    resuelto = ejecutar_resolver(account, ticket, resultado, garantia)
    return "No se pudo resolver el expediente: #{resuelto.message}" if resuelto.is_a?(StandardError)

    registrar_datos_ia(ticket, producto_nombre, detalle_de(garantia))
    dejar_nota_privada(tool_context, ticket, resultado)
    respuesta_segun_autonomia(account, ticket, resultado)
  end
  # rubocop:enable Metrics/ParameterLists

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : nil
  end

  # Arma el bloque de garantia SOLO si el resultado la abre. Los codigos de
  # garantia (ciudad, y si vienen motivo y detalle) deben existir en el catalogo
  # ANTES de tocar el dominio: una ciudad invalida crearia un radicado sin ciudad
  # ni proceso, en silencio. Devuelve: nil (no abre garantia), el hash de garantia,
  # o un String de recuperacion con la lista vigente si un codigo es invalido.
  def construir_garantia(account, resultado, codigos)
    return nil unless resultado.abre_garantia?

    ciudad = Helic3::Catalogo::CoberturaCiudad.activos.find_by(account: account, codigo: codigos[:ciudad_codigo])
    return ciudades_invalidas(account) if ciudad.nil?

    motivo = catalogo_opcional(Helic3::Catalogo::MotivoGarantia, account, codigos[:motivo_garantia_codigo])
    return motivos_garantia_invalidos(account) if invalido?(codigos[:motivo_garantia_codigo], motivo)

    detalle = catalogo_opcional(Helic3::Catalogo::DetalleTipificado, account, codigos[:detalle_tipificado_codigo])
    return detalles_invalidos(account) if invalido?(codigos[:detalle_tipificado_codigo], detalle)

    { cobertura_ciudad: ciudad,
      items: [{ producto_nombre: codigos[:producto_nombre], producto_referencia: codigos[:producto_referencia],
                motivo_garantia: motivo, detalle_tipificado: detalle }] }
  end

  # el detalle que se guardo en la garantia, para replicarlo en la ficha con ia
  def detalle_de(garantia)
    garantia.is_a?(Hash) ? garantia[:items].first[:detalle_tipificado] : nil
  end

  # una corrida: convierte el fallo de dominio en el propio error (texto para el
  # modelo) sin tumbar el run, y deja rastro en el log.
  def ejecutar_resolver(account, ticket, resultado, garantia)
    Helic3::Casos::Resolver.new(ticket: ticket, resultado: resultado, origen: :agente, garantia: garantia).call
  rescue StandardError => e
    Rails.logger.error("[Helic3] resolver_pqr fallo account=#{account.id}: #{e.class}: #{e.message}")
    e
  end

  # DAT-01: lo que el agente dedujo (producto y detalle) entra al expediente con
  # fuente ia, por el mismo servicio que usa el panel. La precedencia protege al
  # operador: si una persona ya corrigio un campo, esta escritura ia no lo pisa.
  def registrar_datos_ia(ticket, producto_nombre, detalle)
    campos = {}
    campos[:producto_nombre] = producto_nombre if producto_nombre.present?
    campos[:detalle_tipificado_id] = detalle.id if detalle
    return if campos.empty?

    Helic3::Casos::RegistrarDatos.new(ticket: ticket, campos: campos, fuente: :ia).call
  end

  # resuelve un codigo OPCIONAL de catalogo: nil si no vino; la fila si existe; y
  # nil tambien si vino uno que no existe (invalido? lo detecta para cortar).
  def catalogo_opcional(modelo, account, codigo)
    return nil if codigo.blank?

    modelo.activos.find_by(account: account, codigo: codigo)
  end

  # vino un codigo pero no resolvio: hay que cortar y devolver la lista vigente.
  def invalido?(codigo, registro)
    codigo.present? && registro.nil?
  end

  # el operador ve que decidio el agente sin abrir otra pantalla
  def dejar_nota_privada(tool_context, ticket, resultado)
    display_id = tool_context.state[:conversation_id]
    return if display_id.blank?

    nota = "Resolucion del agente — expediente #{ticket.numero_radicado || ticket.ticket_number}: " \
           "resultado #{resultado.nombre}."
    with_api_error_handling do
      client(tool_context).create_message(display_id, content: nota, private_note: true)
    end
  end

  # aprobacion humana: la tool NUNCA le anuncia al cliente una negativa ni un
  # desenlace; el caso queda en revision. Autonomia propone/ejecuta para el resto.
  def respuesta_segun_autonomia(account, ticket, resultado)
    if resultado.aprobacion_humana?
      return 'El caso quedo registrado y en revision por el equipo. Confirmale al cliente que su ' \
             'solicitud esta en gestion, SIN adelantar un resultado (ni negativa ni aprobacion).'
    end

    if autonomia(account) == 'ejecuta' && ticket.garantia
      "Expediente resuelto. Numero de radicado de garantia: #{ticket.garantia.numero_radicado}. " \
        'Entregaselo al cliente como confirmacion.'
    elsif autonomia(account) == 'ejecuta'
      'Expediente resuelto. Confirmale al cliente el desenlace de su caso.'
    else
      'Expediente resuelto internamente; queda pendiente de confirmacion del operador. Confirmale al ' \
        'cliente que su caso quedo gestionado, SIN entregarle numeros de radicado.'
    end
  end

  # ante la duda, modo conservador: sin parametro o valor desconocido = "propone".
  def autonomia(account)
    valor = Helic3::Catalogo::Parametro
            .find_by(account_id: account.id, clave: PARAMETRO_AUTONOMIA)
            &.valor
    valor == 'ejecuta' ? 'ejecuta' : 'propone'
  end

  # recuperacion barata: el modelo se inventa un codigo, y la respuesta le da la
  # lista vigente (leida del catalogo) para que reintente en la misma corrida.
  def resultados_invalidos(account)
    lista_vigente(account, Helic3::Catalogo::Resultado, 'resultado_codigo', 'resultados')
  end

  def ciudades_invalidas(account)
    lista_vigente(account, Helic3::Catalogo::CoberturaCiudad, 'ciudad_codigo', 'ciudades')
  end

  def motivos_garantia_invalidos(account)
    lista_vigente(account, Helic3::Catalogo::MotivoGarantia, 'motivo_garantia_codigo', 'motivos de garantia')
  end

  def detalles_invalidos(account)
    lista_vigente(account, Helic3::Catalogo::DetalleTipificado, 'detalle_tipificado_codigo', 'detalles tipificados')
  end

  def lista_vigente(account, modelo, parametro, etiqueta)
    codigos = modelo.activos.where(account: account).pluck(:codigo).join(', ')
    "No se resolvio. #{parametro} invalido; #{etiqueta} vigentes: #{codigos}. Reintenta con uno de la lista."
  end
end
