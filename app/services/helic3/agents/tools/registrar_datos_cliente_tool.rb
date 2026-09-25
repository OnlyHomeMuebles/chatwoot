# frozen_string_literal: true

# H3A-17: la herramienta con la que el agente GUARDA en la ficha del expediente
# los datos que el cliente le da o le CONFIRMA en el chat (cedula, direccion,
# ciudad, numero de factura). Mientras no haya ERP conectado, esta es la via para
# que esos datos entren de forma estructurada y no se queden solo en el hilo.
#
# No contiene logica de dominio (un servicio, varios consumidores: la logica de
# precedencia vive en Helic3::Casos::RegistrarDatos, la misma del panel). Esta
# tool solo TRADUCE entre el mundo del modelo (texto) y el dominio: ubica el
# expediente vigente de la conversacion, llama al servicio con fuente
# `confirmado` y deja rastro para el operador.
#
# Fuente `confirmado` (no `ia`): el dato lo dijo el CLIENTE, no lo dedujo el
# modelo. Por eso le gana al ERP desactualizado pero no a la correccion de una
# persona (precedencia humano > confirmado > erp > ia).
class Helic3::Agents::Tools::RegistrarDatosClienteTool < Helic3::Agents::Tools::BaseTool
  ETIQUETAS = { cedula: 'cédula', direccion: 'dirección', ciudad: 'ciudad',
                factura_numero: 'número de factura', producto_nombre: 'producto' }.freeze

  description 'Guarda en el expediente los datos del caso que salen del chat: cédula, dirección, ' \
              'ciudad, número de factura y el producto sobre el que es la garantía/reclamo. Úsala ' \
              'DESPUÉS de radicar. Cédula, dirección, ciudad y factura solo si el cliente los dio; el ' \
              'producto lo deduces de lo que el cliente ya describió. Nunca inventes. Pasa lo que tengas.'

  param :cedula, type: 'string', required: false,
                 desc: 'Cédula del titular, si el cliente la dio o confirmó.'
  param :direccion, type: 'string', required: false,
                    desc: 'Dirección del cliente, confirmada por él (útil para visita o recolección).'
  param :ciudad, type: 'string', required: false,
                 desc: 'Ciudad del cliente, confirmada por él.'
  param :factura_numero, type: 'string', required: false,
                         desc: 'Número de factura u orden, si el cliente lo dio.'
  param :producto_nombre, type: 'string', required: false,
                          desc: 'Producto sobre el que es el caso (p. ej. "cama", "silla de comedor"), ' \
                                'deducido de lo que el cliente describió. No lo preguntes aparte si ya lo dijo.'

  # la firma la dicta el contrato de parametros de la tool (los que ve el modelo), no el estilo.
  # rubocop:disable Metrics/ParameterLists
  def perform(tool_context, cedula: nil, direccion: nil, ciudad: nil, factura_numero: nil, producto_nombre: nil)
    account = resolve_account(tool_context)
    return 'No hay una cuenta configurada para guardar datos.' if account.blank?

    campos = { cedula: cedula, direccion: direccion, ciudad: ciudad,
               factura_numero: factura_numero, producto_nombre: producto_nombre }.compact_blank
    if campos.empty?
      return 'No recibí ningún dato para guardar. Pídele al cliente al menos uno (cédula, dirección, ' \
             'ciudad, número de factura) o deduce el producto de lo que describió, y guárdalo.'
    end

    ticket = ticket_vigente(account, tool_context)
    if ticket.nil?
      return 'Todavía no hay un expediente radicado en esta conversación. Radica primero con ' \
             'radicar_pqr y luego guarda los datos del cliente.'
    end

    Helic3::Casos::RegistrarDatos.new(ticket: ticket, campos: campos, fuente: :confirmado).call
    dejar_nota_privada(tool_context, ticket, campos)
    "Datos guardados en el expediente #{ticket.numero_radicado || ticket.ticket_number}: " \
      "#{lista(campos)}. No los vuelvas a pedir."
  end
  # rubocop:enable Metrics/ParameterLists

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : nil
  end

  # el expediente VIGENTE de la conversacion (respondida_at: nil), igual criterio
  # que la idempotencia de radicar_pqr: los datos entran al caso en curso.
  def ticket_vigente(account, tool_context)
    display_id = tool_context.state[:conversation_id]
    return nil if display_id.blank?

    conversation_id = account.conversations.find_by(display_id: display_id)&.id
    return nil if conversation_id.blank?

    account.tickets.where(conversation_id: conversation_id, respondida_at: nil).first
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
