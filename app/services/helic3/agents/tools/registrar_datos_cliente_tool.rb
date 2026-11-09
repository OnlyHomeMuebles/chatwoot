# frozen_string_literal: true

# H3A-17: la herramienta con la que el agente GUARDA en la ficha del expediente
# los datos que el cliente le da o le CONFIRMA en el chat.
#
# No contiene logica de dominio: ubica el expediente vigente de la conversacion,
# llama al servicio y deja rastro para el operador. Fuente `confirmado` (no `ia`):
# el dato lo dijo el CLIENTE, no lo dedujo el modelo. Le gana al ERP desactualizado
# pero no a la correccion de una persona (humano > confirmado > erp > ia).
#
# ERP-16 (C2): con el ERP encendido y una cedula, guarda por Helic3::Casos::RegistrarDesdeErp,
# el mismo camino del formulario manual: lo que cruza con Siesa queda erp, lo que el cliente
# corrigio queda confirmado, y la compra queda con los productos elegidos de la factura. Sin
# ERP (o sin cedula), guarda como antes, todo confirmado.
class Helic3::Agents::Tools::RegistrarDatosClienteTool < Helic3::Agents::Tools::BaseTool
  ETIQUETAS = { cedula: 'cédula', direccion: 'dirección', ciudad: 'ciudad',
                cliente_nombre: 'nombre', cliente_telefono: 'teléfono', cliente_email: 'correo',
                factura_numero: 'número de factura', factura_fecha: 'fecha de compra',
                productos: 'productos de la factura', producto_nombre: 'producto' }.freeze

  description 'Guarda en el expediente los datos del caso: cédula, nombre, teléfono, correo, dirección, ' \
              'ciudad, número y fecha de la factura, y los productos del caso. Úsala DESPUÉS de radicar. ' \
              'Si consultaste el ERP, pasa los datos tal como el cliente los confirmó o corrigió, y en ' \
              'productos las referencias que el cliente eligió de la factura. Nunca inventes. Pasa lo que tengas.'

  param :cedula, type: 'string', required: false,
                 desc: 'Cédula del titular, si el cliente la dio o confirmó.'
  param :cliente_nombre, type: 'string', required: false,
                         desc: 'Nombre del cliente, confirmado o corregido por él.'
  param :cliente_telefono, type: 'string', required: false,
                           desc: 'Teléfono del cliente, confirmado o corregido por él.'
  param :cliente_email, type: 'string', required: false,
                        desc: 'Correo del cliente, confirmado o corregido por él.'
  param :direccion, type: 'string', required: false,
                    desc: 'Dirección del cliente, confirmada por él (útil para visita o recolección).'
  param :ciudad, type: 'string', required: false,
                 desc: 'Ciudad del cliente, confirmada por él.'
  param :factura_numero, type: 'string', required: false,
                         desc: 'Número de la factura del caso, tal como lo muestra el ERP si lo consultaste.'
  param :factura_fecha, type: 'string', required: false,
                        desc: 'Fecha de la factura (AAAA-MM-DD), si el cliente la dio y no vino del ERP.'
  param :productos, type: 'string', required: false,
                    desc: 'Referencias de los productos de la factura sobre los que es el caso, ' \
                          'separadas por coma (p. ej. "MIL-200, CER-050"), tal como las mostró el ERP.'
  param :producto_nombre, type: 'string', required: false,
                          desc: 'Producto del caso cuando NO está en la factura del ERP o no hay ERP ' \
                                '(p. ej. "cama"), deducido de lo que el cliente describió.'

  # la firma la dicta el contrato de parametros de la tool (los que ve el modelo), no el estilo.
  # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
  def perform(tool_context, cedula: nil, cliente_nombre: nil, cliente_telefono: nil, cliente_email: nil,
              direccion: nil, ciudad: nil, factura_numero: nil, factura_fecha: nil, productos: nil,
              producto_nombre: nil)
    account = resolve_account(tool_context)
    return 'No hay una cuenta configurada para guardar datos.' if account.blank?

    campos = { cedula: cedula, cliente_nombre: cliente_nombre, cliente_telefono: cliente_telefono,
               cliente_email: cliente_email, direccion: direccion, ciudad: ciudad,
               factura_numero: factura_numero, factura_fecha: factura_fecha, productos: productos,
               producto_nombre: producto_nombre }.compact_blank
    if campos.empty?
      return 'No recibí ningún dato para guardar. Pídele al cliente al menos uno (cédula, dirección, ' \
             'ciudad, número de factura) o deduce el producto de lo que describió, y guárdalo.'
    end

    ticket = ticket_vigente(account, tool_context)
    if ticket.nil?
      return 'Todavía no hay un expediente radicado en esta conversación. Radica primero con ' \
             'radicar_pqr y luego guarda los datos del cliente.'
    end

    guardar(ticket, campos)
    dejar_nota_privada(tool_context, ticket, campos)
    "Datos guardados en el expediente #{ticket.numero_radicado || ticket.ticket_number}: " \
      "#{lista(campos)}. No los vuelvas a pedir."
  rescue ActiveRecord::RecordInvalid => e
    "No se pudieron guardar los datos: #{e.record.errors.full_messages.to_sentence}. Revisa el dato con el " \
    'cliente y vuelve a intentar.'
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : nil
  end

  # el expediente vigente de la conversacion, con la misma regla que la radicacion
  # (ERP-06/T2): el que bloquea una nueva radicacion es el caso en curso.
  def ticket_vigente(account, tool_context)
    display_id = tool_context.state[:conversation_id]
    return nil if display_id.blank?

    conversation_id = account.conversations.find_by(display_id: display_id)&.id
    Helic3::Casos::ExpedienteVigente.para(account: account, conversation_id: conversation_id)
  end

  # Con ERP y cedula (la de esta llamada o la que ya quedo en la ficha), por el camino del
  # formulario; si no, como antes, todo confirmado.
  def guardar(ticket, campos)
    cedula = campos[:cedula].presence || ticket.datos&.cedula
    unless Helic3::Erp.habilitado? && cedula.present?
      return Helic3::Casos::RegistrarDatos.new(ticket: ticket, campos: campos.except(:productos),
                                               fuente: :confirmado).call
    end

    Helic3::Casos::RegistrarDesdeErp.new(ticket: ticket, datos: datos_erp(campos, cedula), fuente: :confirmado).call
  end

  # Las referencias elegidas se cruzan contra la factura; el producto escrito a mano solo cuenta
  # si no se eligio ninguna (si no, se sumaria como un item mas de la garantia).
  def datos_erp(campos, cedula)
    referencias = campos[:productos].to_s.split(',').map(&:strip).compact_blank
    datos = campos.except(:productos).merge(cedula: cedula)
    return datos if referencias.empty?

    datos.except(:producto_nombre).merge(productos: referencias.map { |ref| { referencia: ref } })
  end

  # el operador ve en el hilo que el agente completo la ficha, sin abrir otra pantalla
  def dejar_nota_privada(tool_context, ticket, campos)
    display_id = tool_context.state[:conversation_id]
    return if display_id.blank?

    nota = 'Datos del cliente (confirmados en el chat) — expediente ' \
           "#{ticket.numero_radicado || ticket.ticket_number}: #{lista(campos)}."
    with_api_error_handling do
      client(tool_context).create_message(display_id, content: nota, message_type: 'activity')
    end
  end

  def lista(campos)
    campos.map { |campo, valor| "#{ETIQUETAS.fetch(campo, campo)} #{valor}" }.join(', ')
  end
end
