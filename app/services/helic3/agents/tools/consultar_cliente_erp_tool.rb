# frozen_string_literal: true

# ERP-06: la herramienta con la que el agente CONSULTA el ERP (Siesa) por cedula y trae, en texto,
# los datos del cliente y sus facturas para presentarselos y que el cliente los CONFIRME. No guarda
# nada (eso lo hace registrar_datos_cliente con fuente confirmado): solo TRADUCE la consulta del
# dominio (Helic3::Erp::Cache, la misma que usa el wizard manual) al texto que el modelo relata.
#
# El ERP nunca bloquea al agente: si esta apagado, la cedula es invalida o Siesa cae, la tool
# devuelve un aviso para que el agente siga a mano (precedencia: lo que el cliente confirme luego
# le gana al ERP). La ciudad llega como codigo en Siesa (no nombre), por eso puede quedar vacia.
class Helic3::Agents::Tools::ConsultarClienteErpTool < Helic3::Agents::Tools::BaseTool
  ERP_APAGADO = 'El ERP no está disponible ahora. Pídele los datos al cliente y guárdalos a mano ' \
                'con registrar_datos_cliente.'
  CEDULA_INVALIDA = 'Esa cédula no parece válida. Pídele al cliente que la revise y vuelve a intentar.'
  SIN_CUENTA = 'No hay una cuenta configurada para consultar el ERP.'
  ERP_CAIDO = 'El ERP no responde en este momento. Puedes seguir a mano: pídele los datos al cliente ' \
              'y guárdalos con registrar_datos_cliente.'

  description 'Consulta el ERP (Siesa) por la cédula del cliente y trae sus datos (nombre, teléfono, ' \
              'correo, dirección) y sus facturas con sus productos. Úsala cuando tengas la cédula (del ' \
              'chat o de la foto de la factura). Si tienes el número de factura (del chat o leído de la ' \
              'foto), pásalo para identificar la factura del caso. Después muéstrale los datos y la ' \
              'factura al cliente y pídele que los confirme o corrija ANTES de guardarlos con ' \
              'registrar_datos_cliente. Nunca inventes datos.'

  param :cedula, type: 'string', required: true,
                 desc: 'Cédula del titular tal como la dio el cliente o se leyó de la foto (se normaliza sola).'
  param :factura_numero, type: 'string', required: false,
                         desc: 'Número de factura del caso, si el cliente lo dio o se leyó de la foto, en ' \
                               'cualquier formato (FV-1102, FV 0001102, 1102).'

  def perform(tool_context, cedula:, factura_numero: nil)
    return ERP_APAGADO unless Helic3::Erp.habilitado?

    normalizada = Helic3::Erp.normalizar_cedula(cedula)
    return CEDULA_INVALIDA if normalizada.blank?

    account = resolve_account(tool_context)
    return SIN_CUENTA if account.blank?

    resultado = Helic3::Erp::Cache.consultar(account: account, cedula: normalizada)
    presentar(resultado, normalizada, factura_numero)
  rescue Helic3::Erp::NoDisponible
    ERP_CAIDO
  end

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : nil
  end

  def presentar(resultado, cedula, factura_numero)
    cliente = resultado.cliente
    if cliente.nil?
      return "No encontré a nadie con la cédula #{cedula} en el ERP. Pídele los datos al cliente " \
             'y guárdalos a mano con registrar_datos_cliente.'
    end

    [factura_adjunta(resultado.compras, factura_numero),
     datos_cliente(cliente, cedula),
     facturas(resultado.compras),
     'Muéstrale estos datos (nombre, teléfono, correo, dirección y la factura con sus productos) al ' \
     'cliente y pídele que los confirme o corrija. Pregúntale la ciudad (el ERP no la trae). Luego ' \
     'guárdalos con registrar_datos_cliente, con las referencias de los productos del caso.'].compact.join("\n\n")
  end

  # ERP-16 (C4): si llego un numero de factura (del chat o leido de la foto), se busca entre las
  # facturas del cliente sin dejarselo al modelo. Va de primero en la respuesta. nil si no llego.
  def factura_adjunta(compras, factura_numero)
    return nil if factura_numero.blank?

    candidatas = Array(compras).select { |f| Helic3::Erp.misma_factura?(f.numero, factura_numero) }
    return factura_no_cruza(factura_numero) unless candidatas.one?

    factura = candidatas.first
    detalle = ["La factura que mencionó o adjuntó el cliente (#{factura_numero}) es la #{factura.numero} " \
               "del #{factura.fecha}.", *productos(factura)]
    detalle << if factura.items.one?
                 'Tiene un solo producto: ese es el del caso. Confírmaselo al cliente.'
               else
                 'Tiene varios productos: propón el que coincide con lo que describió el cliente y ' \
                   'confírmaselo antes de guardarlo.'
               end
    detalle.join("\n")
  end

  def factura_no_cruza(factura_numero)
    "La factura #{factura_numero} no aparece entre las facturas de esta cédula en el ERP (puede estar a " \
      'nombre de otra cédula, ser más vieja que el periodo que se consulta o no haber cabido en la ' \
      'consulta). Muéstrale al cliente la lista de abajo para que elija sobre cuál es el caso.'
  end

  def datos_cliente(cliente, cedula)
    [
      "Cliente en el ERP (cédula #{cedula}):",
      "- Nombre: #{cliente.nombre}",
      "- Teléfono: #{cliente.telefono.presence || '—'}",
      "- Correo: #{cliente.email.presence || '—'}",
      "- Dirección: #{cliente.direccion.presence || '—'}",
      "- Ciudad: #{cliente.ciudad.presence || 'no disponible en el ERP'}"
    ].join("\n")
  end

  def facturas(compras)
    return 'Sin facturas en el ERP para esta cédula.' if compras.blank?

    lineas = compras.flat_map do |f|
      partes = ["- #{f.numero} del #{f.fecha}", "total #{formato_pesos(f.total)}"]
      partes << "estado #{f.estado}" if f.estado.present? # algunas facturas de Siesa no traen estado
      [partes.join(' · '), *productos(f).map { |linea| "  #{linea}" }]
    end
    (["Facturas (#{compras.size}):"] + lineas).join("\n")
  end

  # ERP-16 (C1): los productos de cada factura, para que el cliente diga sobre cual es el caso.
  def productos(factura)
    Array(factura.items).map { |item| "- #{item.descripcion} (referencia #{item.referencia})" }
  end

  # Pesos colombianos con separador de miles, sin decimales (lo que el cliente espera leer).
  def formato_pesos(valor)
    "$#{valor.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse}"
  end
end
