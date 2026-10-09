# IND-01: los indicadores de garantias que hoy se consultan en el Dash CX (Apps
# Script externo), calculados con las tablas propias del modulo. Todo se resuelve
# con GROUP BY y, por cada desglose, una consulta aparte para traducir ids a
# nombres (UNA consulta por tabla, nunca dentro de un bucle) -- el numero de
# consultas no crece con el volumen de garantias.
#
# Unidad de conteo (decision de Karen, confirmada 6-oct): las tarjetas y el
# detalle mensual/trimestral/ciudad cuentan RADICADOS (helic3_garantias, una
# solicitud con varios productos es un solo radicado); los desgloses por
# motivo, detalle y proceso cuentan PRODUCTOS (helic3_garantia_items), porque
# un mismo radicado puede tener un producto resuelto y otro en curso bajo
# motivos distintos.
class Helic3::Indicadores::Garantias
  TOP_PRODUCTOS = 20

  # abierta_at es un timestamp sin zona en UTC. Agrupar/filtrar directo sobre esa
  # columna corre el riesgo de que una garantia abierta el 31 a las 9pm en Bogota
  # (2am UTC del dia siguiente) caiga en el mes/trimestre equivocado, lo cual
  # tambien podria desalinear estas cifras frente al Dash CX en los cierres de
  # mes. Se convierte explicitamente a la zona del modulo antes de truncar/extraer.
  FECHA_LOCAL = "(abierta_at AT TIME ZONE 'UTC') AT TIME ZONE '#{Helic3::CalendarioHabil::ZONA}'".freeze

  def self.call(account:, filtros: {})
    new(account: account, filtros: filtros).call
  end

  def initialize(account:, filtros: {})
    @account = account
    @filtros = filtros
  end

  def call
    {
      kpis: kpis,
      mensual: mensual,
      trimestral: trimestral,
      por_ciudad: por_ciudad,
      por_motivo: por_motivo,
      por_detalle: por_detalle,
      por_proceso: por_proceso,
      por_producto: por_producto
    }
  end

  private

  attr_reader :account, :filtros

  def kpis
    base = garantias_filtradas
    {
      garantias: base.count,
      solucionadas: base.where.not(cerrada_at: nil).count,
      en_proceso: base.where(cerrada_at: nil).count,
      productos: items_filtrados.count
    }
  end

  # DATE_TRUNC agrupa por anio+mes a la vez (no solo "mes del calendario"), asi
  # datos de anios distintos nunca se mezclan en la misma barra.
  def mensual
    agrupar_por_fecha("DATE_TRUNC('month', #{FECHA_LOCAL})") { |fecha| fecha.strftime('%Y-%m') }
  end

  def trimestral
    agrupar_por_fecha("DATE_TRUNC('quarter', #{FECHA_LOCAL})") { |fecha| "#{fecha.year}-T#{((fecha.month - 1) / 3) + 1}" }
  end

  # CA: "no aparecen meses posteriores al actual" -- se descarta cualquier grupo
  # cuya fecha truncada caiga despues de este mes, sin importar el anio filtrado.
  # La fecha agrupada llega sin zona (DATE_TRUNC sobre FECHA_LOCAL ya la resto),
  # asi que el limite tambien se calcula en hora de Bogota, no en UTC.
  def agrupar_por_fecha(expresion_sql)
    limite = Time.current.in_time_zone(Helic3::CalendarioHabil::ZONA).to_date.end_of_month
    garantias_filtradas.group(Arel.sql(expresion_sql)).count
                       .filter_map { |fecha, cantidad| { clave: yield(fecha), cantidad: cantidad } if fecha.to_date <= limite }
                       .sort_by { |fila| fila[:clave] }
                       .map { |fila| { periodo: fila[:clave], cantidad: fila[:cantidad] } }
  end

  def por_ciudad
    conteos = garantias_filtradas.group(:cobertura_ciudad_id).count
    nombres = Helic3::Catalogo::CoberturaCiudad.where(id: conteos.keys.compact).pluck(:id, :nombre).to_h
    ordenar_por_cantidad(conteos) { |id| nombres[id] }
  end

  def por_motivo
    conteos = items_filtrados.group(:motivo_garantia_id).count
    nombres = Helic3::Catalogo::MotivoGarantia.where(id: conteos.keys.compact).pluck(:id, :nombre).to_h
    ordenar_por_cantidad(conteos) { |id| nombres[id] }
  end

  def por_detalle
    conteos = items_filtrados.group(:detalle_tipificado_id).count
    nombres = Helic3::Catalogo::DetalleTipificado.where(id: conteos.keys.compact).pluck(:id, :nombre).to_h
    ordenar_por_cantidad(conteos) { |id| nombres[id] }
  end

  def por_proceso
    conteos = items_filtrados.group(:proceso_id).count
    nombres = Helic3::Catalogo::ProcesoGarantia.where(id: conteos.keys.compact).pluck(:id, :nombre).to_h
    ordenar_por_cantidad(conteos) { |id| nombres[id] }
  end

  def por_producto
    items_filtrados.group(:producto_nombre).count
                   .map { |nombre, cantidad| { etiqueta: nombre, cantidad: cantidad } }
                   .sort_by { |fila| -fila[:cantidad] }
                   .first(TOP_PRODUCTOS)
  end

  def ordenar_por_cantidad(conteos)
    conteos.map { |id, cantidad| { etiqueta: yield(id), cantidad: cantidad } }
           .sort_by { |fila| -fila[:cantidad] }
  end

  def garantias_filtradas
    scope = Helic3::Garantia.where(account: account)
    anio = filtro_entero(:anio)
    mes = filtro_entero(:mes)
    scope = scope.where("EXTRACT(year FROM #{FECHA_LOCAL}) = ?", anio) if anio
    scope = scope.where("EXTRACT(month FROM #{FECHA_LOCAL}) = ?", mes) if mes
    scope = scope.where(cobertura_ciudad_id: filtros[:cobertura_ciudad_id]) if filtros[:cobertura_ciudad_id].present?
    filtrar_por_item(scope)
  end

  # N1 (revision de Jhan, PR #113): anio/mes no numericos (p. ej. un parametro
  # manipulado) hacian que Postgres comparara numeric con texto y tumbaran la
  # consulta con un 500. Un valor invalido simplemente se ignora, como si no
  # se hubiera filtrado.
  def filtro_entero(clave)
    Integer(filtros[clave])
  rescue ArgumentError, TypeError
    nil
  end

  # columna directa del item -> filtro del mismo nombre (mismo patron de
  # PqrController#aplicar_filtros: reduce en vez de un if por filtro).
  FILTROS_ITEM_DIRECTOS = %i[motivo_garantia_id detalle_tipificado_id proceso_id].freeze

  # Los filtros de producto viven en el ITEM, no en la garantia; dejan pasar el
  # radicado si AL MENOS un item cumple, sin duplicarlo (id IN subquery, no un
  # join que multiplicaria la fila por cada item que haga match).
  def filtrar_por_item(scope)
    return scope unless filtro_de_item?

    items = FILTROS_ITEM_DIRECTOS.reduce(Helic3::GarantiaItem.where(account: account)) do |acc, columna|
      filtros[columna].present? ? acc.where(columna => filtros[columna]) : acc
    end
    items = items.where('producto_nombre ILIKE ?', "%#{filtros[:producto]}%") if filtros[:producto].present?

    scope.where(id: items.select(:garantia_id))
  end

  def filtro_de_item?
    filtros.values_at(*FILTROS_ITEM_DIRECTOS, :producto).any?(&:present?)
  end

  # Los desgloses por producto/motivo/detalle/proceso cuentan PRODUCTOS de las
  # garantias YA filtradas (incluye todos los items del radicado, no solo el
  # que hizo match con el filtro -- filtrar por motivo "tela motosa" debe seguir
  # mostrando el resto de productos de esa misma garantia en los demas desgloses).
  def items_filtrados
    Helic3::GarantiaItem.where(garantia_id: garantias_filtradas.select(:id))
  end
end
