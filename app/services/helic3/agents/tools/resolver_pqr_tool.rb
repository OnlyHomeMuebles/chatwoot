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

  # ticket_display_id: el expediente a resolver (el numero visible que el agente ya
  # radico o que el operador le dio en el contexto).
  param :ticket_display_id, type: 'string',
                            desc: 'Numero del expediente PQR a resolver (el que se radico antes).'
  param :resultado_codigo, type: 'string',
                           desc: 'Codigo del resultado segun el catalogo de la cuenta (resuelta_info, ' \
                                 'procede_garantia...). Ante un codigo invalido, responde la lista vigente.'
  # solo para el caso de garantia; opcionales para el resto de resultados
  param :ciudad_codigo, type: 'string', required: false,
                        desc: 'Codigo de la ciudad de cobertura; obligatorio si el resultado abre garantia.'
  param :producto_nombre, type: 'string', required: false,
                          desc: 'Nombre del producto en garantia; obligatorio si el resultado abre garantia.'

  def perform(tool_context, ticket_display_id:, resultado_codigo:, ciudad_codigo: nil, producto_nombre: nil)
    account = resolve_account(tool_context)
    return 'No hay una cuenta configurada para resolver.' if account.blank?

    ticket = account.tickets.find_by(display_id: ticket_display_id)
    return "No existe el expediente ##{ticket_display_id} en esta cuenta." if ticket.nil?

    resultado = Helic3::Catalogo::Resultado.activos.find_by(account: account, codigo: resultado_codigo)
    return resultados_invalidos(account) if resultado.nil?

    resuelto = begin
      Helic3::Casos::Resolver.new(
        ticket: ticket, resultado: resultado, origen: :agente,
        garantia: datos_garantia(account, resultado, ciudad_codigo, producto_nombre)
      ).call
    rescue StandardError => e
      Rails.logger.error("[Helic3] resolver_pqr fallo account=#{account.id}: #{e.class}: #{e.message}")
      e
    end
    return "No se pudo resolver el expediente: #{resuelto.message}" if resuelto.is_a?(StandardError)

    registrar_datos_ia(ticket, producto_nombre)
    dejar_nota_privada(tool_context, ticket, resultado)
    respuesta_segun_autonomia(account, ticket, resultado)
  end

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : nil
  end

  # DAT-01: lo que el agente dedujo entra al expediente con fuente ia, por el
  # mismo servicio que usa el panel. La precedencia protege al operador: si una
  # persona ya corrigio el producto, esta escritura ia no lo pisa.
  def registrar_datos_ia(ticket, producto_nombre)
    return if producto_nombre.blank?

    Helic3::Casos::RegistrarDatos.new(
      ticket: ticket, campos: { producto_nombre: producto_nombre }, fuente: :ia
    ).call
  end

  # solo arma el bloque de garantia cuando el resultado la abre; para el resto,
  # nil (Resolver ni lo mira). La ciudad se resuelve contra el catalogo.
  def datos_garantia(account, resultado, ciudad_codigo, producto_nombre)
    return nil unless resultado.abre_garantia?

    ciudad = Helic3::Catalogo::CoberturaCiudad.find_by(account: account, codigo: ciudad_codigo)
    { cobertura_ciudad: ciudad, items: [{ producto_nombre: producto_nombre }] }
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
    codigos = Helic3::Catalogo::Resultado.activos.where(account: account).pluck(:codigo).join(', ')
    "No se resolvio. resultado_codigo invalido; resultados vigentes: #{codigos}. Reintenta con uno de la lista."
  end
end
