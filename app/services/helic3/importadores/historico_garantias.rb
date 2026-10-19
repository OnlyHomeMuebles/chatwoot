# IND-04 (carga historica): puebla helic3_garantias/helic3_garantia_items a
# partir de un export historico del sistema anterior (columnas del Dash CX:
# Consecutivo, Centros de operacion, Fecha de creacion, Proceso PQR, Motivo,
# Detalle Tipificado, productos, Ciudad...), ya convertido a CSV. Se corre
# una sola vez por archivo desde rails runner, mismo criterio que
# Seeders::AccountSeeder (CLAUDE.md):
#
#   Helic3::Importadores::HistoricoGarantias.new(account: Account.find(<id>), ruta: '/ruta/archivo.csv').importar!
#
# Idempotente: cada fila guarda su "Consecutivo" original en
# pqrs_metadata->>'consecutivo_legado'; una fila ya importada se salta, asi
# que correr el mismo archivo dos veces no duplica nada.
#
# Los catalogos (ciudad, motivo, detalle, proceso) del archivo legado nunca
# coinciden letra por letra con los nombres ya sembrados (acentos, mayusculas,
# una que otra palabra distinta). Se normaliza acento/mayuscula/puntuacion y,
# para el puñado de variantes que ni asi calzan, hay un alias explicito uno a
# uno (nunca una coincidencia aproximada automatica). Lo que de verdad no
# tiene equivalente en el catalogo (una ciudad sin cobertura, un motivo que
# no existe hoy) se deja sin asignar -- cae en "Sin ciudad"/"Sin motivo" del
# propio dashboard, nunca se inventa una fila de catalogo nueva.
class Helic3::Importadores::HistoricoGarantias
  ZONA = Helic3::CalendarioHabil::ZONA
  FUENTE = 'ARCHIVO PQRs solucionadas.xlsx'.freeze

  Resultado = Struct.new(
    :creados, :omitidos, :fallidos, :sin_ciudad, :sin_motivo, :sin_detalle, :sin_proceso,
    keyword_init: true
  )

  # Variantes del sistema legado que no coinciden ni siquiera normalizando
  # acentos/mayusculas -- typos ya existentes en el catalogo sembrado
  # ("leventada", "decolorado" en plural) o texto abreviado del export.
  ALIAS_DETALLE = {
    'chapilla levantada' => 'chapilla leventada',
    'desiste de garantia' => 'desiste de la garantia',
    'producto decolorado' => 'productos decolorado'
  }.freeze

  ALIAS_PROCESO = {
    'cambio producto' => 'cambio de producto',
    'ruta en fabrica' => 'reparacion en fabrica',
    'entrega producto' => 'entrega de producto'
  }.freeze

  def initialize(account:, ruta:)
    @account = account
    @ruta = ruta
  end

  def importar!
    contador = Hash.new(0)
    fallidos = []

    CSV.foreach(ruta, headers: true, encoding: 'bom|utf-8') do |fila|
      procesar_fila(fila, contador, fallidos)
    end

    Resultado.new(
      creados: contador[:creados], omitidos: contador[:omitidos], fallidos: fallidos,
      sin_ciudad: contador[:sin_ciudad], sin_motivo: contador[:sin_motivo],
      sin_detalle: contador[:sin_detalle], sin_proceso: contador[:sin_proceso]
    )
  end

  private

  attr_reader :account, :ruta

  def procesar_fila(fila, contador, fallidos)
    consecutivo = fila['Consecutivo']&.strip
    return if consecutivo.blank?

    if ya_importado?(consecutivo)
      contador[:omitidos] += 1
      return
    end

    begin
      importar_fila!(fila, consecutivo, contador)
      contador[:creados] += 1
    rescue ActiveRecord::RecordInvalid => e
      fallidos << { consecutivo: consecutivo, error: e.message }
    end
  end

  def importar_fila!(fila, consecutivo, contador)
    catalogos = catalogos_de(fila, contador)

    ActiveRecord::Base.transaction(requires_new: true) do
      ticket = crear_ticket!(fila, consecutivo)
      garantia = crear_garantia!(fila, ticket, catalogos)
      crear_item!(fila, garantia, catalogos)
    end
  end

  # columna del CSV -> [metodo de mapeo, contador de "sin X" si no mapea]
  MAPEO_CATALOGOS = {
    ciudad_id: ['Ciudad', :ciudad_id_de, :sin_ciudad],
    motivo_id: ['Motivo', :motivo_id_de, :sin_motivo],
    detalle_id: ['Detalle Tipificado', :detalle_id_de, :sin_detalle],
    proceso_id: ['Proceso PQR', :proceso_id_de, :sin_proceso]
  }.freeze

  def catalogos_de(fila, contador)
    MAPEO_CATALOGOS.to_h do |clave, (columna, metodo, contador_sin)|
      id = send(metodo, fila[columna])
      contador[contador_sin] += 1 if id.nil? && presente(fila[columna])
      [clave, id]
    end
  end

  def crear_ticket!(fila, consecutivo)
    Helic3::Ticket.create!(
      account: account,
      title: titulo_de(fila, consecutivo),
      status: :resolved,
      pqrs_prioridad: presente(fila['Prioridad']),
      pqrs_metadata: metadata_de(fila, consecutivo).compact
    )
  end

  def crear_garantia!(fila, ticket, catalogos)
    Helic3::Garantia.create!(
      account: account, ticket: ticket,
      abierta_at: fecha_bogota(fila['Fecha de creación']), cerrada_at: fecha_bogota(fila['Fecha de Finalizacion']),
      cobertura_ciudad_id: catalogos[:ciudad_id]
    )
  end

  def crear_item!(fila, garantia, catalogos)
    proceso_id = catalogos[:proceso_id]
    proceso_terminal = proceso_id && Helic3::Catalogo::ProcesoGarantia.find(proceso_id).es_terminal?

    Helic3::GarantiaItem.create!(
      account: account, garantia: garantia,
      producto_nombre: presente(fila['productos']) || 'Producto no especificado',
      motivo_garantia_id: catalogos[:motivo_id], detalle_tipificado_id: catalogos[:detalle_id],
      proceso_id: proceso_id, resuelto_at: proceso_terminal ? fecha_bogota(fila['Fecha de Finalizacion']) : nil
    )
  end

  def ya_importado?(consecutivo)
    Helic3::Ticket.where(account: account)
                  .exists?(["pqrs_metadata->>'consecutivo_legado' = ?", consecutivo])
  end

  def titulo_de(fila, consecutivo)
    presente(fila['Cliente']) || presente(fila['Cliente potencial']) || "Garantía histórica ##{consecutivo}"
  end

  def metadata_de(fila, consecutivo)
    {
      origen: 'historico',
      consecutivo_legado: consecutivo,
      fuente: FUENTE,
      cliente: presente(fila['Cliente']) || presente(fila['Cliente potencial']),
      telefono: presente(fila['Telefono de contacto']),
      responsable: presente(fila['Responsable']),
      centro_operacion: presente(fila['Centros de operacion'])
    }
  end

  def presente(valor)
    return nil if valor.blank? || valor == '--'

    valor
  end

  # El export es del sistema interno colombiano: las fechas vienen en hora de
  # Bogota, no UTC. Se interpretan explicitamente en esa zona antes de
  # guardar (la columna queda en UTC) para que el agrupamiento mensual del
  # propio dashboard (que convierte UTC -> Bogota) reproduzca el mismo dia
  # calendario del archivo original, igual que el resto del modulo (B1,
  # PR #113).
  def fecha_bogota(valor)
    return nil unless presente(valor)

    ActiveSupport::TimeZone[ZONA].parse(valor)
  end

  def normalizar(texto)
    texto.to_s.unicode_normalize(:nfd).gsub(/[̀-ͯ]/, '')
         .downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end

  def ciudad_id_de(valor)
    return nil unless presente(valor)

    clave = normalizar(valor)
    clave = 'bogota' if clave.start_with?('bogota')
    ciudades_por_nombre[clave]
  end

  def motivo_id_de(valor)
    return nil unless presente(valor)

    motivos_por_nombre[normalizar(valor)]
  end

  def detalle_id_de(valor)
    return nil unless presente(valor)

    clave = normalizar(valor)
    detalles_por_nombre[ALIAS_DETALLE[clave] || clave]
  end

  def proceso_id_de(valor)
    return nil unless presente(valor)

    clave = normalizar(valor)
    procesos_por_nombre[ALIAS_PROCESO[clave] || clave]
  end

  def ciudades_por_nombre
    @ciudades_por_nombre ||= indexar(Helic3::Catalogo::CoberturaCiudad)
  end

  def motivos_por_nombre
    @motivos_por_nombre ||= indexar(Helic3::Catalogo::MotivoGarantia)
  end

  def detalles_por_nombre
    @detalles_por_nombre ||= indexar(Helic3::Catalogo::DetalleTipificado)
  end

  def procesos_por_nombre
    @procesos_por_nombre ||= indexar(Helic3::Catalogo::ProcesoGarantia)
  end

  def indexar(modelo)
    modelo.where(account: account).pluck(:id, :nombre).to_h { |id, nombre| [normalizar(nombre), id] }
  end
end
