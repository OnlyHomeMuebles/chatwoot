# Resumen combinado de Garantias y Derechos de Peticion (vista "Todas las PQR"
# del Dash CX/mockup): un vistazo rapido de los dos expedientes juntos, sin
# mezclar sus tablas -- cada uno sigue siendo su propio modelo con su propio
# reloj (Garantia: presupuesto de dias habiles; PQR: plazo legal de 15 dias
# habiles).
#
# Revision de Jhan (PR #134): toda garantia nace de resolver una PQR ya
# radicada (Helic3::Casos::AbrirGarantia, llamado desde Helic3::Casos::Resolver)
# -- sumar "cantidad de garantias" + "cantidad de PQR" como si fueran universos
# distintos contaba el mismo caso dos veces. El universo real de "casos" es el
# de PQR radicadas (toda garantia cuelga de una); la garantia solo decide si
# ese caso sigue en_proceso o ya esta solucionado.
#
# Filtros: solo anio/mes, los unicos que tienen el mismo significado en
# ambos expedientes. Ciudad/motivo/etapa no entran: los catalogos de
# Garantia y PQR son distintos (L-16), mezclarlos en un solo filtro
# confundiria mas de lo que ayuda.
class Helic3::Indicadores::Todas
  # mismo criterio que Helic3::Indicadores::Pqr::FECHA_LOCAL: radicada_at es un
  # timestamp sin zona en UTC, se convierte a la zona del modulo antes de
  # filtrar por anio/mes para no perder casos radicados tarde en la noche en
  # Bogota. Se duplica aqui (no se expone la de Pqr) para no reabrir ese
  # servicio ya aprobado (PR #130) solo para esta consulta.
  FECHA_LOCAL = "(radicada_at AT TIME ZONE 'UTC') AT TIME ZONE '#{Helic3::CalendarioHabil::ZONA}'".freeze

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

  # Casos totales = PQR radicadas: toda garantia ya cuelga de una, asi que la
  # PQR es el universo completo de casos. Las garantias se muestran como
  # desglose (cuantas de esas PQR terminaron abriendo una), nunca sumadas al
  # total -- sumarlas contaria el mismo caso dos veces.
  def kpis
    total = casos.count
    en_proceso = casos_en_proceso.count
    {
      total_casos: total,
      garantias: garantias[:kpis][:garantias],
      pqr: total,
      solucionadas: total - en_proceso,
      en_proceso: en_proceso
    }
  end

  # En proceso = la PQR todavia no se respondio, O su garantia (si abrio una)
  # todavia no cierra. Solucionado es lo que no cae aqui: respondida Y sin
  # garantia abierta.
  def casos_en_proceso
    casos.left_joins(:garantia)
         .where(
           'helic3_tickets.respondida_at IS NULL OR ' \
           '(helic3_garantias.id IS NOT NULL AND helic3_garantias.cerrada_at IS NULL)'
         )
  end

  def casos
    scope = account.tickets.cuenta_para_sic.where.not(radicada_at: nil)
    anio = filtro_entero(:anio)
    mes = filtro_entero(:mes)
    scope = scope.where("EXTRACT(year FROM #{FECHA_LOCAL}) = ?", anio) if anio
    scope = scope.where("EXTRACT(month FROM #{FECHA_LOCAL}) = ?", mes) if mes
    scope
  end

  # N1 (mismo criterio de Garantias/Pqr, PR #113): anio/mes no numericos se
  # ignoran en vez de tumbar la consulta con un error de Postgres.
  def filtro_entero(clave)
    Integer(filtros[clave])
  rescue ArgumentError, TypeError
    nil
  end

  # Cada servicio ya agrupa por separado (y ya descarta meses futuros, B1);
  # aqui solo se unen por periodo. El total es el de PQR (mismo criterio que
  # el KPI: la garantia es desglose, no se vuelve a sumar).
  def periodos_combinados(filas_garantias, filas_pqr)
    por_periodo = Hash.new { |hash, periodo| hash[periodo] = { periodo: periodo, garantias: 0, pqr: 0 } }
    filas_garantias.each { |fila| por_periodo[fila[:periodo]][:garantias] = fila[:cantidad] }
    filas_pqr.each { |fila| por_periodo[fila[:periodo]][:pqr] = fila[:cantidad] }
    por_periodo.values
               .map { |fila| fila.merge(total: fila[:pqr]) }
               .sort_by { |fila| fila[:periodo] }
  end
end
