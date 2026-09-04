# frozen_string_literal: true

# AGT-01: la herramienta con la que el agente registra DE VERDAD lo que ya le
# promete al cliente. No contiene logica de radicacion (un servicio, dos
# consumidores: la logica vive en Helic3::Casos::Radicar) — esta tool solo
# TRADUCE entre el mundo del modelo (codigos y texto) y el dominio: resuelve
# codigos contra el catalogo, convierte errores en texto reutilizable por el
# modelo, deja la nota privada para el operador y aplica la politica de
# autonomia para decidir que devuelve.
class Helic3::Agents::Tools::RadicarPqrTool < Helic3::Agents::Tools::BaseTool
  PARAMETRO_AUTONOMIA = 'autonomia_radicar_pqr'

  description 'Radica formalmente el caso del cliente como expediente PQR (crea el registro real ' \
              'en el sistema, con su numero y su fecha de vencimiento en dias habiles). Usala cuando ' \
              'ya tengas claros el tipo y el motivo del caso.'

  # Los codigos vigentes son DATOS por cuenta y no se escriben aqui a mano:
  # el agente los recibe en sus instrucciones (leidos del catalogo, AGT-02) y
  # esta tool los enumera de nuevo, leidos del catalogo, si recibe uno
  # invalido — agregar un motivo nuevo jamas obliga a tocar este archivo.
  param :tipo_codigo, type: 'string',
                      desc: 'Codigo del tipo de PQR segun el catalogo de la cuenta (peticion, queja, ' \
                            'reclamo...). Ante un codigo invalido, la herramienta responde la lista vigente.'
  param :motivo_codigo, type: 'string',
                        desc: 'Codigo del motivo de PQR segun el catalogo de la cuenta; de el se deriva ' \
                              'la categoria. Ante un codigo invalido, la herramienta responde la lista vigente.'
  param :resumen, type: 'string', desc: 'Titulo corto del expediente, redactado por ti'
  param :descripcion, type: 'string', desc: 'Lo que reporto el cliente, en sus propios terminos'
  param :numero_orden, type: 'string', required: false,
                       desc: 'Numero de factura u orden, si el cliente lo dio'

  # la firma la dicta el contrato de parametros de la tool (los 5 que ve el
  # modelo), no una decision de estilo
  # rubocop:disable Metrics/ParameterLists
  def perform(tool_context, tipo_codigo:, motivo_codigo:, resumen:, descripcion:, numero_orden: nil)
    account = resolve_account(tool_context)
    return 'No hay una cuenta configurada para radicar.' if account.blank?

    tipo = Helic3::Catalogo::Tipo.activos.find_by(account: account, codigo: tipo_codigo)
    motivo = Helic3::Catalogo::MotivoPqr.activos.find_by(account: account, codigo: motivo_codigo)
    return codigos_invalidos(account, tipo, motivo) if tipo.nil? || motivo.nil?

    ticket = begin
      Helic3::Casos::Radicar.new(
        account: account, titulo: resumen, descripcion: descripcion,
        conversation_id: conversacion_de_bd(account, tool_context),
        tipo: tipo, motivo_pqr: motivo, numero_orden: numero_orden, origen: :agente
      ).call
    rescue StandardError => e
      e
    end
    # un fallo del dominio se vuelve texto legible: el run no se tumba
    return "No se pudo radicar el expediente: #{ticket.message}" if ticket.is_a?(StandardError)

    dejar_nota_privada(tool_context, ticket, tipo, motivo)
    respuesta_segun_autonomia(account, ticket)
  end
  # rubocop:enable Metrics/ParameterLists

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : nil
  end

  # Las tools hablan en display_id (el id publico de la API de Chatwoot); el
  # dominio guarda el id de base de datos. La traduccion vive AQUI, en el
  # adaptador: el display_id es un concepto de Chatwoot, no del dominio.
  def conversacion_de_bd(account, tool_context)
    display_id = tool_context.state[:conversation_id]
    return nil if display_id.blank?

    account.conversations.find_by(display_id: display_id)&.id
  end

  # el operador ve que decidio el agente sin abrir otra pantalla
  def dejar_nota_privada(tool_context, ticket, tipo, motivo)
    display_id = tool_context.state[:conversation_id]
    return if display_id.blank?

    nota = "Radicacion del agente — expediente #{ticket.numero_radicado || ticket.ticket_number}: " \
           "tipo #{tipo.nombre}, motivo #{motivo.nombre} (categoria #{ticket.categoria&.nombre}). " \
           "Vence: #{ticket.plazo_respuesta_vence_at&.to_date || 'sin plazo (no genera radicado)'}."
    with_api_error_handling do
      client(tool_context).create_message(display_id, content: nota, private_note: true)
    end
  end

  def respuesta_segun_autonomia(account, ticket)
    numero = ticket.numero_radicado
    if numero.nil?
      return 'Consulta registrada para historial (la categoria Informacion no genera numero de ' \
             'radicado). Responde la consulta del cliente con normalidad.'
    end

    if autonomia(account) == 'ejecuta'
      "Expediente radicado. Numero de radicado: #{numero}. Entregale este numero al cliente " \
        'como confirmacion de su registro.'
    else
      'Expediente radicado internamente; queda pendiente de confirmacion del operador. ' \
        'Confirmale al cliente que su caso quedo registrado y en gestion, SIN entregarle ' \
        'numero de radicado.'
    end
  end

  # ante la duda, el modo conservador: sin parametro o con un valor
  # desconocido se comporta como "propone". La autonomia sube por
  # configuracion (con evidencia), nunca por accidente.
  def autonomia(account)
    valor = Helic3::Catalogo::Parametro
            .find_by(account_id: account.id, clave: PARAMETRO_AUTONOMIA)
            &.valor
    valor == 'ejecuta' ? 'ejecuta' : 'propone'
  end

  # la recuperacion barata: el modelo se inventa codigos, y la respuesta le
  # da la lista vigente (leida del catalogo) para que reintente en la misma corrida
  def codigos_invalidos(account, tipo, motivo)
    partes = []
    partes << lista_vigente('tipo_codigo', 'tipos', Helic3::Catalogo::Tipo, account) if tipo.nil?
    partes << lista_vigente('motivo_codigo', 'motivos', Helic3::Catalogo::MotivoPqr, account) if motivo.nil?
    "No se radico. #{partes.join(' ')} Reintenta con un codigo de la lista."
  end

  def lista_vigente(parametro, plural, modelo, account)
    codigos = modelo.activos.where(account: account).pluck(:codigo).join(', ')
    "#{parametro} invalido; #{plural} vigentes: #{codigos}."
  end
end
