# Paridad con el Dash CX ("Garantias por motivo"/"Detalle tipificado"): ese
# desglose no es un total plano, es una matriz motivo/detalle x trimestre que
# tambien se puede ver por mes (para el despliegue al hacer click en un
# trimestre). Garantias y Devoluciones comparten exactamente esta forma -- la
# clasificacion (motivo, detalle) vive en el item, la fecha en el radicado
# padre -- asi que viven aqui en vez de duplicarse en cada servicio.
class Helic3::Indicadores::DesgloseTrimestral
  TRIMESTRES = (1..4)

  def initialize(items_con_fecha:, fecha_local_sql:, columna:, catalogo_clase:, campo:)
    @items_con_fecha = items_con_fecha
    @fecha_local_sql = fecha_local_sql
    @columna = columna
    @catalogo_clase = catalogo_clase
    @campo = campo
  end

  def por_trimestre
    conteos = items_con_fecha.group(columna, Arel.sql("EXTRACT(quarter FROM #{fecha_local_sql})")).count
    nombres = nombres_de(conteos.keys.map(&:first))
    conteos.group_by { |(id, _trimestre), _cantidad| id }
           .map { |id, grupo| fila_trimestre(nombres[id], grupo) }
           .sort_by { |fila| -fila[:total] }
  end

  # Mismo criterio que mensual/trimestral del servicio principal: viaja
  # completo en la misma respuesta, el frontend recorta los 3 meses del
  # trimestre que se clickeo (sin un fetch aparte por cada click).
  def por_mes
    limite = Time.current.in_time_zone(Helic3::CalendarioHabil::ZONA).to_date.end_of_month
    conteos = items_con_fecha.group(columna, Arel.sql("DATE_TRUNC('month', #{fecha_local_sql})")).count
    nombres = nombres_de(conteos.keys.map(&:first))
    conteos.filter_map { |(id, fecha), cantidad| fila_mes(nombres[id], fecha, cantidad, limite) }
           .sort_by { |fila| [fila[campo].to_s, fila[:periodo]] }
  end

  private

  attr_reader :items_con_fecha, :fecha_local_sql, :columna, :catalogo_clase, :campo

  def nombres_de(ids)
    catalogo_clase.where(id: ids.compact).pluck(:id, :nombre).to_h
  end

  def fila_trimestre(nombre, grupo)
    por_trimestre = grupo.to_h { |(_id, trimestre), cantidad| [trimestre.to_i, cantidad] }
    fila = { campo => nombre }
    TRIMESTRES.each { |trimestre| fila[:"t#{trimestre}"] = por_trimestre[trimestre] || 0 }
    fila[:total] = por_trimestre.values.sum
    fila
  end

  def fila_mes(nombre, fecha, cantidad, limite)
    return nil if fecha.to_date > limite

    { campo => nombre, :periodo => fecha.strftime('%Y-%m'), :cantidad => cantidad }
  end
end
