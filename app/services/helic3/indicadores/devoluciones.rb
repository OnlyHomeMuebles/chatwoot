# IND-06: indicadores de Devoluciones, expediente hermano de Garantias (mismo
# patron de IND-01: GROUP BY + una consulta de traduccion de ids por tabla).
#
# Unidad de conteo: igual que Garantias -- tarjetas y detalle mensual/
# trimestral/ciudad cuentan RADICADOS (helic3_devoluciones); los desgloses por
# motivo, detalle y proceso cuentan PRODUCTOS (helic3_devolucion_items).
class Helic3::Indicadores::Devoluciones
  TOP_PRODUCTOS = 20
  POR_PAGINA_CASOS = 7
  RANGO_URGENCIA = { rojo: 0, amarillo: 1, verde: 2, sin_presupuesto: 3, resuelta: 4 }.freeze

  FECHA_LOCAL = "(abierta_at AT TIME ZONE 'UTC') AT TIME ZONE '#{Helic3::CalendarioHabil::ZONA}'".freeze
  # FECHA_LOCAL calificada con tabla, para el join con el item (motivo/detalle
  # por trimestre/mes).
  FECHA_LOCAL_ITEM = "(helic3_devoluciones.abierta_at AT TIME ZONE 'UTC') " \
                     "AT TIME ZONE '#{Helic3::CalendarioHabil::ZONA}'".freeze

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
      por_producto: por_producto,
      motivo_por_trimestre: motivo_desglose.por_trimestre,
      motivo_por_mes: motivo_desglose.por_mes,
      detalle_por_trimestre: detalle_desglose.por_trimestre,
      detalle_por_mes: detalle_desglose.por_mes
    }
  end

  # Mismo patron de Garantias#casos: ordena con una clave liviana para TODAS
  # las devoluciones filtradas, y solo las 7 de la pagina final pagan el
  # costo de numero_radicado/cliente/centro/proceso.
  def casos(pagina: 1)
    calendario = Helic3::CalendarioHabil.new
    parametros = Helic3::ParametrosGarantia.desde_catalogo(account, ambito: :garantia)
    ordenadas = devoluciones_filtradas
                .includes(items: :proceso)
                .map { |devolucion| clave_urgencia(devolucion, parametros, calendario) }
                .sort_by { |clave| [clave[:rango], clave[:devolucion_id]] }
    paginar_casos(ordenadas, pagina)
  end

  private

  attr_reader :account, :filtros

  def clave_urgencia(devolucion, parametros, calendario)
    resuelta = devolucion.resuelta?
    presupuesto = resuelta ? nil : devolucion.presupuesto(parametros: parametros, calendario: calendario)
    { devolucion_id: devolucion.id, resuelta: resuelta, presupuesto: presupuesto,
      rango: rango_urgencia_de_caso(resuelta, presupuesto) }
  end

  def filas_de_pagina(claves)
    devoluciones = Helic3::Devolucion.where(id: claves.pluck(:devolucion_id))
                                     .includes(:cobertura_ciudad, items: :proceso, ticket: { conversation: :contact })
                                     .index_by(&:id)
    claves.map { |clave| fila_de_caso(devoluciones.fetch(clave[:devolucion_id]), clave) }
  end

  def fila_de_caso(devolucion, clave)
    conversacion = devolucion.ticket.conversation
    {
      id: devolucion.id,
      numero_radicado: devolucion.numero_radicado,
      cliente: conversacion&.contact&.name,
      centro_operacion: devolucion.cobertura_ciudad&.nombre,
      proceso: devolucion.proceso_visible&.nombre,
      etapa: clave[:resuelta] ? 'solucionada' : 'en_gestion',
      conversation_display_id: conversacion&.display_id,
      vencimiento: vencimiento_de_caso(clave[:resuelta], clave[:presupuesto])
    }
  end

  def vencimiento_de_caso(resuelta, presupuesto)
    return { estado: 'solucionada' } if resuelta

    {
      estado: presupuesto.semaforo.to_s,
      saldo_dias_habiles: presupuesto.saldo,
      fecha_etapa_vigente: presupuesto.fecha_etapa_vigente
    }
  end

  def rango_urgencia_de_caso(resuelta, presupuesto)
    return RANGO_URGENCIA[:resuelta] if resuelta

    RANGO_URGENCIA.fetch(presupuesto.semaforo, RANGO_URGENCIA[:sin_presupuesto])
  end

  def paginar_casos(claves, pagina)
    total = claves.size
    paginas = [(total.to_f / POR_PAGINA_CASOS).ceil, 1].max
    pagina_actual = pagina.to_i.clamp(1, paginas)
    inicio = (pagina_actual - 1) * POR_PAGINA_CASOS
    pagina_de_claves = claves.slice(inicio, POR_PAGINA_CASOS) || []
    { casos: filas_de_pagina(pagina_de_claves), pagina: pagina_actual, paginas: paginas, total: total }
  end

  def kpis
    base = devoluciones_filtradas
    {
      devoluciones: base.count,
      solucionadas: base.where.not(cerrada_at: nil).count,
      en_proceso: base.where(cerrada_at: nil).count,
      productos: items_filtrados.count
    }
  end

  def mensual
    agrupar_por_fecha("DATE_TRUNC('month', #{FECHA_LOCAL})") { |fecha| fecha.strftime('%Y-%m') }
  end

  def trimestral
    agrupar_por_fecha("DATE_TRUNC('quarter', #{FECHA_LOCAL})") { |fecha| "#{fecha.year}-T#{((fecha.month - 1) / 3) + 1}" }
  end

  def agrupar_por_fecha(expresion_sql, &)
    limite = Time.current.in_time_zone(Helic3::CalendarioHabil::ZONA).to_date.end_of_month
    totales = devoluciones_filtradas.group(Arel.sql(expresion_sql)).count
    solucionadas = devoluciones_filtradas.where.not(cerrada_at: nil).group(Arel.sql(expresion_sql)).count
    totales.filter_map { |fecha, cantidad| fila_de_periodo(fecha, cantidad, solucionadas[fecha] || 0, limite, &) }
           .sort_by { |fila| fila[:periodo] }
  end

  def fila_de_periodo(fecha, cantidad, solucionadas, limite)
    return nil if fecha.to_date > limite

    { periodo: yield(fecha), cantidad: cantidad, solucionadas: solucionadas, en_proceso: cantidad - solucionadas }
  end

  # valor (el id) viaja ademas de la etiqueta para el click-to-filter; "sin
  # ciudad" se excluye (no hay tienda con la que compararlo), a diferencia de
  # por_motivo/por_detalle/por_proceso donde "sin dato" si es util.
  def por_ciudad
    conteos = devoluciones_filtradas.where.not(cobertura_ciudad_id: nil).group(:cobertura_ciudad_id).count
    nombres = Helic3::Catalogo::CoberturaCiudad.where(id: conteos.keys).pluck(:id, :nombre).to_h
    conteos.map { |id, cantidad| { etiqueta: nombres[id], valor: id, cantidad: cantidad } }
           .sort_by { |fila| -fila[:cantidad] }
  end

  def por_motivo
    conteos = items_filtrados.group(:motivo_devolucion_id).count
    nombres = Helic3::Catalogo::MotivoDevolucion.where(id: conteos.keys.compact).pluck(:id, :nombre).to_h
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

  # Paridad con el Dash CX ("Garantias por motivo"/"Detalle tipificado"): el
  # calculo (matriz trimestre + despliegue por mes) vive en DesgloseTrimestral,
  # compartido con Garantias; memoizado porque #call pide trimestre y mes.
  def motivo_desglose
    @motivo_desglose ||= desglose(:motivo_devolucion_id, Helic3::Catalogo::MotivoDevolucion, :motivo)
  end

  def detalle_desglose
    @detalle_desglose ||= desglose(:detalle_tipificado_id, Helic3::Catalogo::DetalleTipificado, :detalle)
  end

  def desglose(columna, catalogo_clase, campo)
    Helic3::Indicadores::DesgloseTrimestral.new(
      items_con_fecha: items_filtrados.joins(:devolucion), fecha_local_sql: FECHA_LOCAL_ITEM,
      columna: columna, catalogo_clase: catalogo_clase, campo: campo
    )
  end

  def ordenar_por_cantidad(conteos)
    conteos.map { |id, cantidad| { etiqueta: yield(id), cantidad: cantidad } }
           .sort_by { |fila| -fila[:cantidad] }
  end

  def devoluciones_filtradas
    scope = Helic3::Devolucion.where(account: account)
    anio = filtro_entero(:anio)
    mes = filtro_entero(:mes)
    scope = scope.where("EXTRACT(year FROM #{FECHA_LOCAL}) = ?", anio) if anio
    scope = scope.where("EXTRACT(month FROM #{FECHA_LOCAL}) = ?", mes) if mes
    scope = scope.where(cobertura_ciudad_id: filtros[:cobertura_ciudad_id]) if filtros[:cobertura_ciudad_id].present?
    filtrar_por_item(scope)
  end

  def filtro_entero(clave)
    Integer(filtros[clave])
  rescue ArgumentError, TypeError
    nil
  end

  FILTROS_ITEM_DIRECTOS = %i[motivo_devolucion_id detalle_tipificado_id proceso_id].freeze

  def filtrar_por_item(scope)
    return scope unless filtro_de_item?

    items = FILTROS_ITEM_DIRECTOS.reduce(Helic3::DevolucionItem.where(account: account)) do |acc, columna|
      filtros[columna].present? ? acc.where(columna => filtros[columna]) : acc
    end
    items = items.where('producto_nombre ILIKE ?', "%#{filtros[:producto]}%") if filtros[:producto].present?

    scope.where(id: items.select(:devolucion_id))
  end

  def filtro_de_item?
    filtros.values_at(*FILTROS_ITEM_DIRECTOS, :producto).any?(&:present?)
  end

  def items_filtrados
    Helic3::DevolucionItem.where(devolucion_id: devoluciones_filtradas.select(:id))
  end
end
