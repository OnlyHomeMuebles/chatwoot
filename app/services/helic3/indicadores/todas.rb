# Resumen combinado de Garantias y Derechos de Peticion (vista "Todas las PQR"
# del Dash CX/mockup): un vistazo rapido de los dos expedientes juntos, sin
# mezclar sus tablas -- cada uno sigue siendo su propio modelo con su propio
# reloj (Garantia: presupuesto de dias habiles; PQR: plazo legal de 15 dias
# habiles). Esto solo SUMA lo que cada servicio ya calcula por separado.
#
# Filtros: solo anio/mes, los unicos que tienen el mismo significado en
# ambos expedientes. Ciudad/motivo/etapa no entran: los catalogos de
# Garantia y PQR son distintos (L-16), mezclarlos en un solo filtro
# confundiria mas de lo que ayuda.
class Helic3::Indicadores::Todas
  def self.call(account:, filtros: {})
    new(account: account, filtros: filtros).call
  end

  def initialize(account:, filtros: {})
    @account = account
    @filtros = filtros.slice(:anio, :mes)
  end

  def call
    {
      kpis: kpis,
      mensual: periodos_combinados(garantias[:mensual], pqr[:mensual]),
      trimestral: periodos_combinados(garantias[:trimestral], pqr[:trimestral])
    }
  end

  private

  attr_reader :account, :filtros

  def garantias
    @garantias ||= Helic3::Indicadores::Garantias.call(account: account, filtros: filtros)
  end

  def pqr
    @pqr ||= Helic3::Indicadores::Pqr.call(account: account, filtros: filtros)
  end

  def kpis
    {
      total_casos: cantidad_garantias + cantidad_pqr,
      garantias: cantidad_garantias,
      pqr: cantidad_pqr,
      solucionadas: garantias[:kpis][:solucionadas] + pqr[:kpis][:respondidas],
      en_proceso: garantias[:kpis][:en_proceso] + pqr[:kpis][:pendientes]
    }
  end

  def cantidad_garantias
    garantias[:kpis][:garantias]
  end

  def cantidad_pqr
    pqr[:kpis][:radicadas]
  end

  # Cada servicio ya agrupa por separado (y ya descarta meses futuros, B1);
  # aqui solo se unen por periodo, sin recalcular nada.
  def periodos_combinados(filas_garantias, filas_pqr)
    por_periodo = Hash.new { |hash, periodo| hash[periodo] = { periodo: periodo, garantias: 0, pqr: 0 } }
    filas_garantias.each { |fila| por_periodo[fila[:periodo]][:garantias] = fila[:cantidad] }
    filas_pqr.each { |fila| por_periodo[fila[:periodo]][:pqr] = fila[:cantidad] }
    por_periodo.values
               .map { |fila| fila.merge(total: fila[:garantias] + fila[:pqr]) }
               .sort_by { |fila| fila[:periodo] }
  end
end
