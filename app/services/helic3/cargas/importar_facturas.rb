# IND-03 (parcial): sube el CSV de facturas de Siesa y lo vuelca en
# helic3_facturas_venta. Hoy solo CSV -- .xlsx/.txt quedan para cuando el
# conversor de FMT-01 (Helic3::Formatos::Conversor) este disponible aqui;
# no se agrega ninguna gema nueva para leer Excel (mismo criterio del
# documento de tickets, seccion 8).
#
# Columnas requeridas, exactas como las exporta Siesa (confirmadas en el
# Dash CX, seccion "Referencia" del documento de tickets): Nro documento,
# Desc. C.O., Fecha, Valor subtotal.
class Helic3::Cargas::ImportarFacturas
  COLUMNAS_REQUERIDAS = ['Nro documento', 'Desc. C.O.', 'Fecha', 'Valor subtotal'].freeze

  ColumnasFaltantes = Class.new(StandardError)

  def self.call(account:, archivo:, modo:, usuario: nil, nombre_archivo: nil)
    new(account: account, archivo: archivo, modo: modo, usuario: usuario, nombre_archivo: nombre_archivo).call
  end

  def initialize(account:, archivo:, modo:, usuario: nil, nombre_archivo: nil)
    @account = account
    @archivo = archivo
    @modo = modo
    @usuario = usuario
    @nombre_archivo = nombre_archivo || archivo.try(:original_filename) || 'archivo.csv'
  end

  def call
    contenido = leer_contenido
    encabezados = primer_encabezado(contenido)
    verificar_columnas!(encabezados)

    carga = Helic3::Carga.create!(
      account: account, tipo: 'facturas', nombre_archivo: nombre_archivo, modo: modo, usuario: usuario,
      estado: 'procesando'
    )
    procesar_filas!(carga, contenido)
    carga.update!(estado: 'completado')
    carga
  end

  private

  attr_reader :account, :archivo, :modo, :usuario, :nombre_archivo

  # archivo.read en un upload multipart llega en BINARY (ASCII-8BIT); comparar
  # eso contra el literal UTF-8 del BOM revienta con "incompatible character
  # encodings" apenas el CSV trae una tilde o eñe (Siesa siempre exporta en
  # UTF-8). Se reetiqueta explicitamente antes de tocar el contenido.
  def leer_contenido
    contenido = archivo.respond_to?(:read) ? archivo.read : archivo.to_s
    contenido.force_encoding('UTF-8').delete_prefix("\xEF\xBB\xBF")
  end

  def primer_encabezado(contenido)
    CSV.parse_line(contenido.each_line.first.to_s, col_sep: columna_separadora(contenido)) || []
  end

  # Siesa puede exportar con ',' o ';' segun la configuracion regional de
  # quien lo genera; se detecta por la primera linea en vez de asumir una.
  def columna_separadora(contenido)
    primera_linea = contenido.each_line.first.to_s
    primera_linea.count(';') > primera_linea.count(',') ? ';' : ','
  end

  def verificar_columnas!(encabezados)
    normalizados = encabezados.map { |columna| columna.to_s.strip }
    faltantes = COLUMNAS_REQUERIDAS - normalizados
    return if faltantes.empty?

    raise ColumnasFaltantes, "faltan las columnas: #{faltantes.join(', ')}"
  end

  # Un solo UPDATE al final (no uno por fila): los contadores se acumulan en
  # memoria mientras se procesa el CSV completo.
  def procesar_filas!(carga, contenido)
    sep = columna_separadora(contenido)
    contadores = Hash.new(0)
    errores = []

    CSV.parse(contenido, headers: true, col_sep: sep).each.with_index(2) do |fila, numero_fila|
      contadores[:filas_leidas] += 1
      resultado = procesar_fila(carga, fila)
      if resultado.is_a?(String)
        errores << { 'fila' => numero_fila, 'error' => resultado }
        contadores[:filas_omitidas] += 1
      else
        contadores[resultado] += 1
      end
    end

    carga.update!(contadores.merge(errores: errores))
  end

  # Devuelve :filas_insertadas/:filas_actualizadas/:filas_omitidas, o el
  # mensaje de error como String cuando la fila no se pudo guardar.
  def procesar_fila(carga, fila)
    numero_documento = fila['Nro documento'].to_s.strip
    fecha = parsear_fecha(fila['Fecha'])
    valor = parsear_valor(fila['Valor subtotal'])

    return 'fecha o valor ilegible, o falta el numero de documento' if numero_documento.blank? || fecha.nil? || valor.nil?

    guardar_factura(carga, numero_documento, fila['Desc. C.O.'], fecha, valor)
  rescue StandardError => e
    e.message
  end

  def guardar_factura(carga, numero_documento, centro_operacion, fecha, valor)
    existente = Helic3::FacturaVenta.find_by(account: account, numero_documento: numero_documento)

    if existente
      return :filas_omitidas if modo == 'anexar'

      existente.update!(centro_operacion: centro_operacion, fecha: fecha, valor_subtotal: valor, carga: carga)
      :filas_actualizadas
    else
      Helic3::FacturaVenta.create!(
        account: account, carga: carga, numero_documento: numero_documento,
        centro_operacion: centro_operacion, fecha: fecha, valor_subtotal: valor
      )
      :filas_insertadas
    end
  end

  def parsear_fecha(valor)
    Date.parse(valor.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Formato colombiano: el punto SIEMPRE es separador de miles, nunca decimal
  # (una factura redonda sin centavos llega como "1.200.000", no "1200000.00").
  # Se descarta primero, y solo si queda una coma esa es la decimal ("1.234.567,89"
  # -> "1234567,89" -> "1234567.89"). Sin coma, el numero ya es el valor final
  # ("1.200.000" -> "1200000", "500000" -> "500000").
  def parsear_valor(valor)
    texto = valor.to_s.strip
    return nil if texto.blank?

    sin_miles = texto.delete('.')
    normalizado = sin_miles.include?(',') ? sin_miles.tr(',', '.') : sin_miles
    Float(normalizado)
  rescue ArgumentError, TypeError
    nil
  end
end
