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
              'correo, dirección) y sus facturas. Úsala cuando el cliente te dé la cédula. Después ' \
              'muéstrale los datos y pídele que los confirme o corrija ANTES de guardarlos con ' \
              'registrar_datos_cliente. Nunca inventes datos.'

  param :cedula, type: 'string', required: true,
                 desc: 'Cédula del titular tal como la dio el cliente (se normaliza sola).'

  def perform(_tool_context, cedula:)
    return ERP_APAGADO unless Helic3::Erp.habilitado?

    normalizada = Helic3::Erp.normalizar_cedula(cedula)
    return CEDULA_INVALIDA if normalizada.blank?

    account = resolve_account(_tool_context)
    return SIN_CUENTA if account.blank?

    resultado = Helic3::Erp::Cache.consultar(account: account, cedula: normalizada)
    presentar(resultado, normalizada)
  rescue Helic3::Erp::NoDisponible
    ERP_CAIDO
  end

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : nil
  end

  def presentar(resultado, cedula)
    cliente = resultado.cliente
    if cliente.nil?
      return "No encontré a nadie con la cédula #{cedula} en el ERP. Pídele los datos al cliente " \
             'y guárdalos a mano con registrar_datos_cliente.'
    end

    [datos_cliente(cliente, cedula),
     facturas(resultado.compras),
     'Muéstrale estos datos al cliente y pídele que los confirme o corrija antes de guardarlos ' \
     'con registrar_datos_cliente.'].join("\n\n")
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

    lineas = compras.map do |f|
      partes = ["- #{f.numero} del #{f.fecha}", "total #{formato_pesos(f.total)}"]
      partes << "estado #{f.estado}" if f.estado.present? # algunas facturas de Siesa no traen estado
      partes.join(' · ')
    end
    (["Facturas (#{compras.size}):"] + lineas).join("\n")
  end

  # Pesos colombianos con separador de miles, sin decimales (lo que el cliente espera leer).
  def formato_pesos(valor)
    "$#{valor.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse}"
  end
end
