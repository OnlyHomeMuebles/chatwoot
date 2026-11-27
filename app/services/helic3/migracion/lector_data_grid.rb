# frozen_string_literal: true

require 'csv'

# MIG-02 (Pieza 2, capa 1): lee el CSV CRUDO del DataGrid 85 tal como lo descarga
# el CRM anterior y aplica las reglas de limpieza de MIG-01, SIN tocar la base de
# datos. Devuelve los casos agrupados por consecutivo (una fila del CSV = un
# producto) con sus valores ya limpios (todavía como NOMBRES; el mapeo a códigos de
# catálogo lo hace ImportarGarantias en la capa de escritura), más el detalle de
# cada ajuste aplicado, para que el reporte de la simulación lo muestre por caso.
#
# Es puro a propósito: toda la limpieza se prueba con un CSV de muestra sin BD.
class Helic3::Migracion::LectorDataGrid
  # columna del DataGrid (normalizada: sin tildes, minúsculas) => clave interna.
  COLUMNAS = {
    'consecutivo' => :consecutivo,
    'fecha de creacion' => :fecha_creacion,
    'prioridad' => :prioridad,
    'centros de operacion' => :centro_operacion,
    'etapa del caso' => :etapa_caso,
    'proceso pqr' => :proceso,
    'motivo' => :motivo,
    'detalle tipificado' => :detalle,
    'telefono de contacto' => :telefono,
    'fecha de finalizacion' => :fecha_finalizacion,
    'productos' => :producto,
    'seguimiento u/o observaciones' => :observaciones,
    'identificacion' => :cedula,
    'nombre del cliente' => :nombre,
    'apellido del cliente' => :apellido,
    'correo electronico' => :correo,
    'direccion' => :direccion,
    'factura / pedido / orden de compra' => :factura_manual,
    'nro factura' => :factura_numero,
    'ciudad' => :ciudad,
    'fecha ultima compra' => :fecha_compra,
    'tipo identificacion' => :tipo_identificacion
  }.freeze

  MOTIVO_POR_DEFECTO = 'Calidad - Producto Comprado'
  PROCESO_SIN_PROCESO = 'PQR FINALIZADA'
  PRODUCTO_SIN_REGISTRO = 'Producto no registrado en la migración'
  ETAPAS_ABIERTAS = ['en gestion', 'nuevo'].freeze

  def self.leer(csv_texto)
    new(csv_texto).leer
  end

  def initialize(csv_texto)
    @csv_texto = csv_texto.to_s
  end

  def leer
    tabla = CSV.parse(@csv_texto, headers: true)
    faltantes = columnas_faltantes(tabla.headers)
    return { columnas_ok: false, columnas_faltantes: faltantes, casos: [], excluidos: [] } if faltantes.any?

    # mapa header-original => clave interna, una sola vez (no por cada fila)
    @mapa_headers = tabla.headers.each_with_object({}) do |header, mapa|
      clave = COLUMNAS[normalizar(header)]
      mapa[header] = clave if clave
    end
    filas = tabla.map { |fila| limpiar_fila(fila) }
    filas = sin_duplicados(filas)
    casos = agrupar_por_consecutivo(filas)

    casos_ok, excluidos = casos.partition { |caso| !caso_de_prueba?(caso) }
    casos_ok.each { |caso| aplicar_reglas!(caso) }

    { columnas_ok: true, columnas_faltantes: [],
      casos: casos_ok, excluidos: excluidos,
      resumen: { filas: tabla.size, casos: casos_ok.size, excluidos: excluidos.size } }
  end

  private

  # --- columnas ---

  def columnas_faltantes(headers)
    presentes = Array(headers).map { |h| normalizar(h) }
    COLUMNAS.keys - presentes
  end

  # --- limpieza de una fila ---

  def limpiar_fila(fila)
    datos = {}
    @mapa_headers.each { |header, clave| datos[clave] = celda(fila[header]) }
    datos[:cedula] = sin_espacios(datos[:cedula])
    datos[:telefono] = sin_espacios(datos[:telefono])
    datos[:cruda] = fila.fields.map(&:to_s) # para detectar duplicados exactos
    datos
  end

  # trim; "--" y vacío => nil
  def celda(valor)
    texto = valor.to_s.strip
    return nil if texto.empty? || texto == '--'

    texto
  end

  def sin_espacios(texto)
    texto&.gsub(/\s+/, '')
  end

  # --- duplicados exactos ---

  def sin_duplicados(filas)
    vistas = {}
    filas.reject do |fila|
      llave = fila[:cruda]
      if vistas[llave]
        true
      else
        vistas[llave] = true
        false
      end
    end
  end

  # --- agrupar por consecutivo (una fila = un producto) ---

  def agrupar_por_consecutivo(filas)
    filas.group_by { |fila| fila[:consecutivo] }.map do |consecutivo, grupo|
      base = grupo.first
      {
        consecutivo: consecutivo.to_i,
        fecha_creacion: base[:fecha_creacion],
        prioridad: base[:prioridad],
        centro_operacion: base[:centro_operacion],
        etapa_caso: base[:etapa_caso],
        proceso: base[:proceso],
        motivo: base[:motivo],
        observaciones: base[:observaciones],
        cedula: base[:cedula],
        cliente_nombre: [base[:nombre], base[:apellido]].compact.join(' ').presence,
        telefono: base[:telefono],
        correo: base[:correo],
        direccion: base[:direccion],
        ciudad: base[:ciudad],
        factura_numero: base[:factura_numero],
        fecha_compra: base[:fecha_compra],
        tipo_identificacion: base[:tipo_identificacion],
        fecha_finalizacion: base[:fecha_finalizacion],
        productos: grupo.map { |fila| { nombre: fila[:producto], detalle: fila[:detalle] } },
        ajustes: []
      }
    end
  end

  # --- reglas de MIG-01 ---

  def caso_de_prueba?(caso)
    caso[:observaciones].to_s.strip.upcase.start_with?('PRUEBA')
  end

  def aplicar_reglas!(caso)
    if caso[:motivo].blank?
      caso[:motivo] = MOTIVO_POR_DEFECTO
      caso[:ajustes] << "motivo vacío → #{MOTIVO_POR_DEFECTO}"
    end

    abierta = ETAPAS_ABIERTAS.include?(normalizar(caso[:etapa_caso]))
    if abierta && caso[:fecha_finalizacion].present?
      caso[:fecha_finalizacion] = nil
      caso[:ajustes] << 'fecha de finalización quitada (caso en gestión)'
    end

    if !abierta && caso[:proceso].blank?
      caso[:proceso] = PROCESO_SIN_PROCESO
      caso[:ajustes] << "solucionado sin proceso → #{PROCESO_SIN_PROCESO}"
    end

    caso[:productos].each do |producto|
      next if producto[:nombre].present?

      producto[:nombre] = PRODUCTO_SIN_REGISTRO
      caso[:ajustes] << "producto vacío → #{PRODUCTO_SIN_REGISTRO}"
    end
  end

  # sin tildes, minúsculas, espacios colapsados
  def normalizar(texto)
    texto.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.strip.gsub(/\s+/, ' ')
  end
end
