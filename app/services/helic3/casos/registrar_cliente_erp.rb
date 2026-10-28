# frozen_string_literal: true

# ERP-08: al radicar con consultado_erp, escribe en la ficha lo que trajo el ERP con
# fuente erp, y del bloque que mando el agente solo lo que CAMBIO (o lo que el ERP no
# trae) con fuente humano. El backend RECONSULTA el adaptador (no confia en que el
# frontend diga que un dato vino de Siesa) y, si el ERP falla, deja todo humano: el
# ERP nunca bloquea una radicacion.
class Helic3::Casos::RegistrarClienteErp
  # Customer (ERP) -> campos de la ficha (Helic3::TicketDato).
  CAMPO_POR_ATRIBUTO = {
    cedula: :cedula, nombre: :cliente_nombre, telefono: :cliente_telefono,
    email: :cliente_email, ciudad: :ciudad, direccion: :direccion
  }.freeze

  def initialize(ticket:, datos:)
    @ticket = ticket
    @datos = datos.to_h.symbolize_keys # lo que el agente ve/edita en el wizard
    # La cedula se guarda ya normalizada (sin puntos/guion), igual que la que usa el ERP,
    # para que no se marque como correccion humana solo por el formato que tecleo el agente.
    normalizada = Helic3::Erp.normalizar_cedula(@datos[:cedula])
    @datos[:cedula] = normalizada if normalizada
  end

  def call
    cliente = consultar
    return registrar(@datos, :humano) unless cliente

    campos_erp = campos_desde(cliente)
    registrar(campos_erp, :erp)
    registrar(diferencias(campos_erp), :humano)
  end

  private

  # El ERP NUNCA bloquea una radicacion: cualquier fallo de la consulta (timeout, red,
  # config) se trata como "no hay cliente" y se continua a mano (todo humano). Solo se
  # rescata la CONSULTA, no la escritura de la ficha (un fallo ahi si debe salir ruidoso).
  def consultar
    cedula = @datos[:cedula]
    return nil if cedula.blank?

    # ERP-14: lee del cache (lo que el wizard ya consulto); solo llama a Siesa si no hay
    # resultado vigente. Antes re-llamaba al adaptador en cada radicacion.
    Helic3::Erp::Cache.consultar(account: @ticket.account, cedula: cedula).cliente
  rescue StandardError => e
    Rails.logger.warn("[ERP-08] ERP no disponible al radicar ticket #{@ticket.id}: #{e.class.name}")
    nil
  end

  def campos_desde(cliente)
    CAMPO_POR_ATRIBUTO.filter_map do |atributo, campo|
      valor = cliente.public_send(atributo)
      [campo, valor] if valor.present?
    end.to_h
  end

  # Del bloque del agente, lo que DIFIERE del ERP (comparacion sin mayusculas ni espacios
  # de sobra) o lo que el ERP no trajo. Lo que coincide se queda con fuente erp.
  def diferencias(campos_erp)
    @datos.select { |campo, valor| valor.present? && normal(campos_erp[campo]) != normal(valor) }
  end

  def normal(valor)
    valor.to_s.strip.downcase.gsub(/\s+/, ' ')
  end

  def registrar(campos, fuente)
    return if campos.blank?

    Helic3::Casos::RegistrarDatos.new(ticket: @ticket, campos: campos, fuente: fuente).call
  end
end
