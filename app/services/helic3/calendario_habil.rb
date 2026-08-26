# frozen_string_literal: true

# Calendario de días hábiles de Colombia. Resuelve los festivos de cualquier año
# sin depender de una tabla cargada a mano, calculando las tres clases que define
# la ley colombiana:
#
#   1. Fijos: caen siempre en la misma fecha (p. ej. 25 de diciembre).
#   2. Trasladables (Ley 51 de 1983 / "Emiliani"): se corren al lunes siguiente.
#   3. Móviles por Pascua: Jueves y Viernes Santo (no se trasladan) y Ascensión,
#      Corpus Christi y Sagrado Corazón, que se cuentan en días desde el Domingo
#      de Resurrección y además se trasladan al lunes.
#
# Todo se calcula en la zona horaria America/Bogota de forma explícita, nunca la
# del servidor. El calendario de cada año se cachea.
class Helic3::CalendarioHabil
  ZONA = 'America/Bogota'

  # Festivos de fecha fija (mes, día). No se trasladan.
  FIJOS = [[1, 1], [5, 1], [7, 20], [8, 7], [12, 8], [12, 25]].freeze

  # Festivos que la Ley 51 traslada al lunes siguiente (mes, día base).
  TRASLADABLES = [[1, 6], [3, 19], [6, 29], [8, 15], [10, 12], [11, 1], [11, 11]].freeze

  # Festivos móviles contados en días desde el Domingo de Resurrección.
  # :traslada indica si la Ley 51 los corre al lunes siguiente.
  MOVILES = [
    { offset: -3, traslada: false, nombre: 'Jueves Santo' },
    { offset: -2, traslada: false, nombre: 'Viernes Santo' },
    { offset: 39, traslada: true, nombre: 'Ascensión del Señor' },
    { offset: 60, traslada: true, nombre: 'Corpus Christi' },
    { offset: 68, traslada: true, nombre: 'Sagrado Corazón' }
  ].freeze

  # Fecha de hoy en la zona horaria de Colombia (no la del servidor).
  def self.hoy
    Time.find_zone!(ZONA).today
  end

  def initialize
    @festivos_por_anio = {}
  end

  # Devuelve el calendario resuelto del año como { Date => nombre }, ordenado por
  # fecha, para poder auditarlo. Se cachea por año.
  def festivos(anio)
    @festivos_por_anio[anio] ||= calcular_festivos(anio)
  end

  # ¿La fecha cuenta como día hábil? (no fin de semana y no festivo)
  def es_habil?(fecha)
    fecha = fecha.to_date
    return false if fecha.saturday? || fecha.sunday?

    !festivos(fecha.year).key?(fecha)
  end

  # Suma n días hábiles a una fecha y devuelve la fecha resultante.
  # n = 0 devuelve la misma fecha; no acepta negativos.
  def sumar_dias_habiles(fecha, cantidad)
    raise ArgumentError, 'la cantidad de días hábiles no puede ser negativa' if cantidad.negative?

    resultado = fecha.to_date
    restantes = cantidad
    while restantes.positive?
      resultado += 1
      restantes -= 1 if es_habil?(resultado)
    end
    resultado
  end

  # Cuenta los días hábiles en el intervalo (desde, hasta]: excluye la fecha
  # inicial e incluye la final, de modo que sea consistente con sumar_dias_habiles.
  def dias_habiles_entre(desde, hasta)
    desde = desde.to_date
    hasta = hasta.to_date
    return 0 if hasta <= desde

    ((desde + 1)..hasta).count { |fecha| es_habil?(fecha) }
  end

  private

  def calcular_festivos(anio)
    festivos = {}

    FIJOS.each { |mes, dia| festivos[Date.new(anio, mes, dia)] = nombre_fijo(mes, dia) }

    TRASLADABLES.each do |mes, dia|
      festivos[trasladar_a_lunes(Date.new(anio, mes, dia))] = nombre_trasladable(mes, dia)
    end

    pascua = domingo_de_resurreccion(anio)
    MOVILES.each do |movil|
      fecha = pascua + movil[:offset]
      fecha = trasladar_a_lunes(fecha) if movil[:traslada]
      festivos[fecha] = movil[:nombre]
    end

    festivos.sort.to_h
  end

  # Corre la fecha al lunes siguiente (si ya es lunes, se queda). Siempre hacia
  # adelante, como manda la Ley 51.
  def trasladar_a_lunes(fecha)
    fecha + ((1 - fecha.wday) % 7)
  end

  # Domingo de Resurrección por el algoritmo gregoriano anónimo (Meeus/Butcher).
  # Es una fórmula matemática canónica; se deja tal cual por legibilidad.
  def domingo_de_resurreccion(anio) # rubocop:disable Metrics/AbcSize
    a = anio % 19
    b = anio / 100
    c = anio % 100
    d = b / 4
    e = b % 4
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = ((19 * a) + b - d - g + 15) % 30
    i = c / 4
    k = c % 4
    l = (32 + (2 * e) + (2 * i) - h - k) % 7
    m = (a + (11 * h) + (22 * l)) / 451
    mes = (h + l - (7 * m) + 114) / 31
    dia = ((h + l - (7 * m) + 114) % 31) + 1
    Date.new(anio, mes, dia)
  end

  def nombre_fijo(mes, dia)
    {
      [1, 1] => 'Año Nuevo',
      [5, 1] => 'Día del Trabajo',
      [7, 20] => 'Día de la Independencia',
      [8, 7] => 'Batalla de Boyacá',
      [12, 8] => 'Inmaculada Concepción',
      [12, 25] => 'Navidad'
    }[[mes, dia]]
  end

  def nombre_trasladable(mes, dia)
    {
      [1, 6] => 'Reyes Magos',
      [3, 19] => 'San José',
      [6, 29] => 'San Pedro y San Pablo',
      [8, 15] => 'Asunción de la Virgen',
      [10, 12] => 'Día de la Raza',
      [11, 1] => 'Todos los Santos',
      [11, 11] => 'Independencia de Cartagena'
    }[[mes, dia]]
  end
end
