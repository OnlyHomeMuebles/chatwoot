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

  def self.normalizar_encabezado(texto)
    texto.to_s.strip.unicode_normalize(:nfd).gsub(/[̀-ͯ]/, '').downcase
  end

  # Segunda revision de Jhan: antes esto solo se usaba para VALIDAR que las
  # columnas estuvieran (verificar_encabezados!), pero procesar_fila seguia
  # leyendo con la grafia exacta (fila['Nro documento']). Un archivo con
  # "NRO DOCUMENTO" pasaba la validacion y despues cada fila leia nil --
  # la carga terminaba "completado" con 0 insertadas, en silencio. Ahora el
  # mismo mapeo normalizado->canonico se usa para VALIDAR y para LEER (como
  # header_converter de CSV.parse), asi los dos caminos nunca pueden
  # desincronizarse.
  CANONICOS_POR_NORMALIZADO = COLUMNAS_REQUERIDAS.index_by { |columna| normalizar_encabezado(columna) }.freeze

  def self.convertir_encabezado(encabezado)
    CANONICOS_POR_NORMALIZADO.fetch(normalizar_encabezado(encabezado), encabezado)
  end

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
    encabezados_convertidos = primer_encabezado(contenido).map { |columna| convertir_encabezado(columna) }
    faltantes = COLUMNAS_REQUERIDAS - encabezados_convertidos
    return if faltantes.empty?

    raise ColumnasFaltantes, "faltan las columnas: #{faltantes.join(', ')}"
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
  rescue StandardError => e
    # Segunda revision de Jhan: si revienta antes de terminar (archivo
    # corrupto, error de infraestructura), el mensaje quedaba solo en el log
    # -- el admin veia "fallido" sin saber por que. Se guarda en errores,
    # igual que un error de fila, para que se vea en el historial.
    carga.update!(estado: 'fallido', errores: carga.errores + [{ 'fila' => nil, 'error' => e.message }])
    raise
  end

  private

  attr_reader :carga, :account

  def modo
    carga.modo
  end

  # archivo.download (ActiveStorage) llega en BINARY (ASCII-8BIT). Siesa
  # exporta en UTF-8, pero si alguien abre el CSV en Excel y lo re-guarda
  # (Karen, revision de Jhan) suele quedar en Windows-1252 -- se detecta por
  # validez de encoding en vez de asumir siempre UTF-8.
  def leer_contenido
    crudo = carga.archivo.download
    utf8 = crudo.dup.force_encoding('UTF-8')
    contenido = utf8.valid_encoding? ? utf8 : crudo.force_encoding('Windows-1252').encode('UTF-8')
    contenido.delete_prefix("\xEF\xBB\xBF")
  end

  def columna_separadora(contenido)
    self.class.columna_separadora(contenido)
  end

  # Un solo UPDATE al final (no uno por fila): los contadores se acumulan en
  # memoria mientras se procesa el CSV completo. header_converters normaliza
  # cada encabezado real al nombre canonico (ver CANONICOS_POR_NORMALIZADO):
  # el resto del codigo siempre lee fila['Nro documento'], sin importar como
  # vino escrito en el archivo.
  #
  # Segunda revision de Jhan (no bloqueante, pedido explicito de Juan): un
  # find_by + create!/update! por fila eran hasta 33.000 SELECT + 33.000
  # INSERT/UPDATE en el archivo real. Ahora se arma un solo lote en memoria y
  # se guarda con insert_all/upsert_all -- dos consultas en total (la precarga
  # de existentes y el lote), sin importar cuantas filas traiga el archivo.
  def procesar_filas!(contenido)
    sep = columna_separadora(contenido)
    filas = CSV.parse(contenido, headers: true, col_sep: sep,
                                 header_converters: ->(encabezado) { self.class.convertir_encabezado(encabezado) })
    existentes = precargar_existentes(filas)
    contadores = Hash.new(0)
    errores = []
    # Hash, no Array: si el mismo numero de documento se repite DENTRO del
    # archivo, el lote solo puede llevar una fila por llave unica -- Postgres
    # revienta un upsert que intente afectar la misma fila dos veces en la
    # misma sentencia. Queda la ULTIMA ocurrencia, igual que si se guardaran
    # una por una en orden (la ultima pisa a la anterior).
    por_guardar = {}

    filas.each.with_index(2) do |fila, numero_fila|
      contadores[:filas_leidas] += 1
      clasificar_fila(fila, existentes, contadores, por_guardar) do |mensaje_error|
        errores << { 'fila' => numero_fila, 'error' => mensaje_error }
      end
    end

    guardar_en_lote!(por_guardar.values)
    carga.update!(contadores.merge(errores: errores))
  end

  def precargar_existentes(filas)
    numeros = filas.map { |fila| fila['Nro documento'].to_s.strip }.reject(&:blank?).uniq
    Helic3::FacturaVenta.where(account: account, numero_documento: numeros).pluck(:numero_documento).to_set
  end

  # Decide que hacer con una fila sin tocar la base: la deja lista en
  # por_guardar (si aplica) y actualiza los contadores. existentes se
  # actualiza con cada fila nueva (no solo con lo que ya habia en la base):
  # asi un numero de documento repetido DENTRO del mismo archivo tambien se
  # reconoce como ya visto.
  def clasificar_fila(fila, existentes, contadores, por_guardar)
    numero_documento = fila['Nro documento'].to_s.strip
    fecha = parsear_fecha(fila['Fecha'])
    valor = parsear_valor(fila['Valor subtotal'])

    if numero_documento.blank? || fecha.nil? || valor.nil?
      yield('fecha o valor ilegible, o falta el numero de documento')
      contadores[:filas_omitidas] += 1
      return
    end

    ya_existia = existentes.include?(numero_documento)
    if ya_existia && modo == 'anexar'
      contadores[:filas_omitidas] += 1
      return
    end

    contadores[ya_existia ? :filas_actualizadas : :filas_insertadas] += 1
    existentes << numero_documento
    por_guardar[numero_documento] = {
      account_id: account.id, carga_id: carga.id, numero_documento: numero_documento,
      centro_operacion: fila['Desc. C.O.'], fecha: fecha, valor_subtotal: valor
    }
  end

  # "anexar": insert_all con unique_by hace ON CONFLICT DO NOTHING -- las
  # filas que ya se filtraron como "ya existia" arriba nunca llegan aqui, asi
  # que esto solo inserta genuinamente nuevas. "sobrescribir": upsert_all hace
  # ON CONFLICT DO UPDATE, cubriendo en un solo lote tanto las filas nuevas
  # como las que reemplazan un numero de documento existente.
  # Tercera revision de Jhan: "sobrescribir" debe reemplazar los VALORES de una
  # factura existente, no su carga de origen. Sin update_only, el upsert
  # tambien reescribia carga_id -- la carga que la inserto por primera vez
  # quedaba sin ninguna factura (y se podia borrar del historial aunque
  # dijera "N insertadas"). Con update_only, un conflicto solo actualiza los
  # datos del negocio; carga_id/account_id/numero_documento quedan como
  # estaban en el insert original.
  COLUMNAS_ACTUALIZABLES = %i[centro_operacion fecha valor_subtotal].freeze

  # rubocop:disable Rails/SkipsModelValidations -- deliberado (pedido por Juan,
  # revisado por Jhan): cada fila ya paso por clasificar_fila, que replica las
  # tres validaciones del modelo (presence de numero_documento/fecha,
  # numericality de valor_subtotal) antes de llegar aqui. insert_all/
  # upsert_all cambian las ~33.000 consultas individuales del archivo real por
  # dos en total.
  def guardar_en_lote!(atributos_lista)
    return if atributos_lista.empty?

    if modo == 'sobrescribir'
      Helic3::FacturaVenta.upsert_all(atributos_lista, unique_by: :idx_h3_facturas_account_numero,
                                                       record_timestamps: true, update_only: COLUMNAS_ACTUALIZABLES)
    else
      Helic3::FacturaVenta.insert_all(atributos_lista, unique_by: :idx_h3_facturas_account_numero,
                                                       record_timestamps: true)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Revision de Jhan: Date.parse con un anio de 2 digitos es peligrosamente
  # ambiguo -- Date.parse('05/09/26') da 2005-09-26, no 2026-09-05, sin
  # reventar. Mientras no se confirme el formato exacto del archivo real
  # (CA1), se exige un anio de 4 digitos explicito en el texto; sin eso se
  # omite la fila (queda en errores) en vez de adivinar mal en silencio.
  def parsear_fecha(valor)
    texto = valor.to_s
    return nil unless texto.match?(/\d{4}/)

    Date.parse(texto)
  rescue ArgumentError, TypeError
    nil
  end

  # Formato colombiano: el punto SIEMPRE es separador de miles, nunca decimal
  # (una factura redonda sin centavos llega como "1.200.000", no "1200000.00").
  # Se descarta primero, y solo si queda una coma esa es la decimal ("1.234.567,89"
  # -> "1234567,89" -> "1234567.89"). Sin coma, el numero ya es el valor final
  # ("1.200.000" -> "1200000", "500000" -> "500000").
  #
  # BigDecimal, no Float (revision de Jhan): es plata, no se guarda con
  # imprecision de punto flotante binario.
  #
  # Tercera revision de Jhan: con insert_all/upsert_all en lote, un valor que
  # no cabe en decimal(14,2) ya no revienta solo esa fila -- revienta el lote
  # completo (todo el archivo). Se valida el rango aqui mismo, antes de que
  # llegue al lote: una fila fuera de rango se omite (queda en errores) en vez
  # de tumbar las demas.
  VALOR_MAXIMO = BigDecimal('999999999999.99')

  def parsear_valor(valor)
    texto = valor.to_s.strip
    return nil if texto.blank?

    sin_miles = texto.delete('.')
    normalizado = sin_miles.include?(',') ? sin_miles.tr(',', '.') : sin_miles
    numero = BigDecimal(normalizado)
    return nil if numero.abs > VALOR_MAXIMO

    numero
  rescue ArgumentError, TypeError
    nil
  end
end
