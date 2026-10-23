# IND-03 (parcial): sube el CSV de facturas de Siesa y lo vuelca en
# helic3_facturas_venta. Hoy solo CSV -- .xlsx/.txt quedan para cuando el
# conversor de FMT-01 (Helic3::Formatos::Conversor) este disponible aqui;
# no se agrega ninguna gema nueva para leer Excel (mismo criterio del
# documento de tickets, seccion 8).
#
# Columnas requeridas, exactas como las exporta Siesa (confirmadas en el
# Dash CX, seccion "Referencia" del documento de tickets): Nro documento,
# Desc. C.O., Fecha, Valor subtotal.
#
# Revision de Jhan (PR #140): un archivo real trae ~33.000 filas; procesarlo
# dentro de la peticion (con un find_by por fila) no aguanta. El controlador
# crea la Carga y adjunta el archivo (ActiveStorage, sobrevive la peticion),
# y un job llama a .call -- aqui solo queda la logica de procesamiento sobre
# una Carga ya existente.
class Helic3::Cargas::ImportarFacturas
  COLUMNAS_REQUERIDAS = ['Nro documento', 'Desc. C.O.', 'Fecha', 'Valor subtotal'].freeze

  ColumnasFaltantes = Class.new(StandardError)

  # Chequeo rapido y sincronico, ANTES de crear la Carga o encolar el job: el
  # usuario quiere saber ya si el archivo no sirve, no esperar a que arranque
  # el job para enterarse. Solo lee el encabezado (primera linea).
  def self.verificar_columnas!(archivo)
    primera_linea = archivo.read.force_encoding('UTF-8').delete_prefix("\xEF\xBB\xBF")
    verificar_encabezados!(primera_linea)
  ensure
    archivo.rewind
  end

  # Revision de Jhan: Siesa no siempre manda el encabezado identico -- a veces
  # sin tildes, con mayusculas distintas, o separado por tabulador en vez de
  # ';'/','. Se compara normalizado (sin tildes, minusculas) en vez de exigir
  # una grafia exacta.
  def self.verificar_encabezados!(contenido)
    encabezados = primer_encabezado(contenido).map { |columna| normalizar_encabezado(columna) }
    faltantes = COLUMNAS_REQUERIDAS.reject { |columna| encabezados.include?(normalizar_encabezado(columna)) }
    return if faltantes.empty?

    raise ColumnasFaltantes, "faltan las columnas: #{faltantes.join(', ')}"
  end

  def self.normalizar_encabezado(texto)
    texto.to_s.strip.unicode_normalize(:nfd).gsub(/[̀-ͯ]/, '').downcase
  end

  def self.primer_encabezado(contenido)
    CSV.parse_line(contenido.each_line.first.to_s, col_sep: columna_separadora(contenido)) || []
  end

  # Siesa puede exportar con ',', ';' o tabulador segun quien lo genere; se
  # detecta por la primera linea en vez de asumir uno.
  def self.columna_separadora(contenido)
    primera_linea = contenido.each_line.first.to_s
    conteos = { "\t" => primera_linea.count("\t"), ';' => primera_linea.count(';'), ',' => primera_linea.count(',') }
    conteos.max_by { |_separador, cantidad| cantidad }.first
  end

  def self.call(carga:)
    new(carga: carga).call
  end

  def initialize(carga:)
    @carga = carga
    @account = carga.account
  end

  def call
    contenido = leer_contenido
    self.class.verificar_encabezados!(contenido)
    procesar_filas!(contenido)
    carga.update!(estado: 'completado')
    carga
  rescue StandardError
    carga.update!(estado: 'fallido')
    raise
  end

  private

  attr_reader :carga, :account

  def modo
    carga.modo
  end

  # archivo.download (ActiveStorage) llega en BINARY (ASCII-8BIT), igual que
  # antes llegaba el upload multipart; comparar eso contra el literal UTF-8
  # del BOM revienta con "incompatible character encodings" apenas el CSV
  # trae una tilde o eñe (Siesa siempre exporta en UTF-8). Se reetiqueta
  # explicitamente antes de tocar el contenido.
  def leer_contenido
    carga.archivo.download.force_encoding('UTF-8').delete_prefix("\xEF\xBB\xBF")
  end

  def columna_separadora(contenido)
    self.class.columna_separadora(contenido)
  end

  # Un solo UPDATE al final (no uno por fila): los contadores se acumulan en
  # memoria mientras se procesa el CSV completo. precargar_existentes trae en
  # UNA consulta las facturas que ya existen -- antes se hacia un find_by por
  # fila (hasta 33.000 consultas en el archivo real, revision de Jhan).
  def procesar_filas!(contenido)
    sep = columna_separadora(contenido)
    filas = CSV.parse(contenido, headers: true, col_sep: sep)
    existentes = precargar_existentes(filas)
    contadores = Hash.new(0)
    errores = []

    filas.each.with_index(2) do |fila, numero_fila|
      contadores[:filas_leidas] += 1
      resultado = procesar_fila(fila, existentes)
      if resultado.is_a?(String)
        errores << { 'fila' => numero_fila, 'error' => resultado }
        contadores[:filas_omitidas] += 1
      else
        contadores[resultado] += 1
      end
    end

    carga.update!(contadores.merge(errores: errores))
  end

  def precargar_existentes(filas)
    numeros = filas.map { |fila| fila['Nro documento'].to_s.strip }.reject(&:blank?).uniq
    Helic3::FacturaVenta.where(account: account, numero_documento: numeros).index_by(&:numero_documento)
  end

  # Devuelve :filas_insertadas/:filas_actualizadas/:filas_omitidas, o el
  # mensaje de error como String cuando la fila no se pudo guardar.
  def procesar_fila(fila, existentes)
    numero_documento = fila['Nro documento'].to_s.strip
    fecha = parsear_fecha(fila['Fecha'])
    valor = parsear_valor(fila['Valor subtotal'])

    return 'fecha o valor ilegible, o falta el numero de documento' if numero_documento.blank? || fecha.nil? || valor.nil?

    guardar_factura(numero_documento, fila['Desc. C.O.'], fecha, valor, existentes)
  rescue StandardError => e
    e.message
  end

  # existentes se actualiza con cada fila nueva (no solo con lo que ya habia
  # en la base): asi un numero de documento repetido DENTRO del mismo archivo
  # tambien se reconoce como ya visto, sin otra consulta.
  def guardar_factura(numero_documento, centro_operacion, fecha, valor, existentes)
    existente = existentes[numero_documento]

    if existente
      return :filas_omitidas if modo == 'anexar'

      existente.update!(centro_operacion: centro_operacion, fecha: fecha, valor_subtotal: valor, carga: carga)
      :filas_actualizadas
    else
      existentes[numero_documento] = Helic3::FacturaVenta.create!(
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
