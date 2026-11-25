# frozen_string_literal: true

# GAR-09: estado de vigencia de la garantía de un expediente. Se calcula contra la
# fecha de RADICACIÓN (no la de hoy): un caso que entró dentro del amparo no cambia
# de estado mientras se atiende. Informa, no bloquea; la excepción de la madera va
# solo en el texto del aviso (el cálculo no mira el detalle tipificado).
#
# El plazo sale del parámetro amparo_garantia (el mismo que lee pqrs_agent): ningún
# número de negocio vive aquí. Devuelve datos crudos (símbolos, fechas, enteros); el
# frontend arma los textos con i18n.
class Helic3::VigenciaGarantia
  ZONA = Helic3::CalendarioHabil::ZONA
  CLAVE_AMPARO = 'amparo_garantia'

  def self.para(ticket)
    new(ticket).calcular
  end

  def initialize(ticket)
    @ticket = ticket
  end

  # nil cuando el expediente no es de garantía (no se pinta aviso) o cuando falta el
  # parámetro en la cuenta (no rompe el expediente, solo no avisa + log del error).
  def calcular
    return nil unless expediente_de_garantia?

    amparo = amparo_meses
    return nil if amparo.nil?

    {
      estado: estado(amparo),
      fecha_radicacion: fecha_radicacion,
      factura_fecha: factura_fecha,
      amparo_meses: amparo,
      amparo_hasta: amparo_hasta(amparo),
      antiguedad_meses: antiguedad_meses
    }
  end

  private

  # Solo en expedientes de categoría Garantía o que ya tengan una garantía abierta.
  def expediente_de_garantia?
    @ticket.categoria&.codigo == 'garantia' || @ticket.garantia.present?
  end

  def amparo_meses
    parametro = Helic3::Catalogo::Parametro.find_by(account: @ticket.account, clave: CLAVE_AMPARO)
    valor = parametro&.valor_entero
    if valor.nil?
      Rails.logger.error("[VigenciaGarantia] falta el parámetro #{CLAVE_AMPARO} (cuenta #{@ticket.account_id})")
      return nil
    end
    valor
  end

  def factura_fecha
    return @factura_fecha if defined?(@factura_fecha)

    @factura_fecha = @ticket.datos&.factura_fecha
  end

  # radicada_at como fecha (sin hora) en America/Bogota; created_at si viniera nula.
  def fecha_radicacion
    @fecha_radicacion ||= (@ticket.radicada_at || @ticket.created_at).in_time_zone(ZONA).to_date
  end

  def amparo_hasta(amparo)
    return nil unless factura_fecha

    factura_fecha.advance(months: amparo)
  end

  # Comparación inclusiva: el día del vencimiento todavía está dentro.
  def estado(amparo)
    return :sin_fecha_compra unless factura_fecha

    fecha_radicacion <= amparo_hasta(amparo) ? :dentro : :fuera
  end

  # Meses completos entre la compra y la radicación (p. ej. 26 = 2 años y 2 meses).
  def antiguedad_meses
    return nil unless factura_fecha

    meses = ((fecha_radicacion.year - factura_fecha.year) * 12) +
            (fecha_radicacion.month - factura_fecha.month)
    meses -= 1 if fecha_radicacion.day < factura_fecha.day
    [meses, 0].max
  end
end
