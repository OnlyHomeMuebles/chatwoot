# IND-02: la pestana "Derechos de Peticion" del Dash CX, resuelta con las PQR
# que ya existen en el CRM (`helic3_tickets`). "Derecho de peticion" no es un
# tipo sembrado -- los tipos reales son Peticion/Queja/Reclamo/Sugerencia/
# Felicitacion -- asi que esta pestana muestra TODAS las PQR con el tipo como
# filtro, igual que explica el ticket (seccion 2: "no es un tipo sembrado").
class Helic3::Indicadores::Pqr
  # radicada_at es un timestamp sin zona en UTC (mismo riesgo que abierta_at en
  # Garantias): convertir a la zona del modulo antes de truncar/extraer evita
  # que una PQR radicada tarde en la noche en Bogota caiga en el mes siguiente.
  FECHA_LOCAL = "(radicada_at AT TIME ZONE 'UTC') AT TIME ZONE '#{Helic3::CalendarioHabil::ZONA}'".freeze

  TRIMESTRES = (1..4)

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
      motivo_por_trimestre: motivo_por_trimestre,
      por_tipo: por_tipo,
      por_categoria: por_categoria,
      por_resultado: por_resultado,
      por_responsable: por_responsable
    }
  end

  private

  attr_reader :account, :filtros

  def kpis
    base = pqr_filtradas
    radicadas = base.count
    respondidas = base.where.not(respondida_at: nil).count
    dentro_plazo = base.where.not(respondida_at: nil).where('respondida_at <= plazo_respuesta_vence_at').count
    vencidas = base.where(respondida_at: nil).where('plazo_respuesta_vence_at < ?', Time.current).count
    {
      radicadas: radicadas,
      respondidas: respondidas,
      pendientes: radicadas - respondidas,
      pct_respondidas: porcentaje(respondidas, radicadas),
      dentro_plazo: dentro_plazo,
      vencidas_sin_responder: vencidas,
      pct_cumplimiento: porcentaje(dentro_plazo, respondidas)
    }
  end

  # "Dentro de plazo"/"% cumplimiento" se calculan sobre RESPONDIDAS, no sobre
  # el total radicado -- una PQR pendiente que todavia no vence no es "exitosa",
  # simplemente no se ha resuelto. Sin denominador, nil (no 0%): un 0% se leeria
  # como incumplimiento real, no como "todavia no hay datos".
  def porcentaje(parte, total)
    return nil if total.zero?

    (parte.to_f / total * 100).round(1)
  end

  def mensual
    agrupar_por_fecha("DATE_TRUNC('month', #{FECHA_LOCAL})") { |fecha| fecha.strftime('%Y-%m') }
  end

  def trimestral
    agrupar_por_fecha("DATE_TRUNC('quarter', #{FECHA_LOCAL})") { |fecha| "#{fecha.year}-T#{((fecha.month - 1) / 3) + 1}" }
  end

  # Mismo patron que Helic3::Indicadores::Garantias#agrupar_por_fecha: dos
  # consultas agrupadas (total y respondidas), no una por fila -- el numero de
  # consultas no crece con el volumen. CA: no aparecen meses posteriores al actual.
  def agrupar_por_fecha(expresion_sql, &)
    limite = Time.current.in_time_zone(Helic3::CalendarioHabil::ZONA).to_date.end_of_month
    totales = pqr_filtradas.group(Arel.sql(expresion_sql)).count
    respondidas = pqr_filtradas.where.not(respondida_at: nil).group(Arel.sql(expresion_sql)).count
    filas = totales.filter_map do |fecha, cantidad|
      fila_de_periodo(fecha, cantidad, respondidas[fecha] || 0, limite, &)
    end
    filas.sort_by { |fila| fila[:periodo] }
  end

  def fila_de_periodo(fecha, cantidad, respondidas, limite)
    return nil if fecha.to_date > limite

    { periodo: yield(fecha), cantidad: cantidad, respondidas: respondidas, pendientes: cantidad - respondidas }
  end

  # Motivo x trimestre (T1-T4, sumando todos los anios que entren por los
  # filtros -- igual que el resto de desgloses, que operan sobre el scope ya
  # filtrado). Una sola consulta agrupada por (motivo, trimestre-del-anio).
  def motivo_por_trimestre
    conteos = pqr_filtradas.group(:motivo_pqr_id, Arel.sql("EXTRACT(quarter FROM #{FECHA_LOCAL})")).count
    motivo_ids = conteos.keys.filter_map(&:first)
    nombres = Helic3::Catalogo::MotivoPqr.where(id: motivo_ids).pluck(:id, :nombre).to_h
    por_motivo = conteos.group_by { |(motivo_id, _trimestre), _cantidad| motivo_id }
    filas = por_motivo.map { |motivo_id, grupo| fila_motivo_trimestre(motivo_id, grupo, nombres) }
    filas.sort_by { |fila| -fila[:total] }
  end

  def fila_motivo_trimestre(motivo_id, grupo, nombres)
    por_trimestre = grupo.to_h { |(_motivo_id, trimestre), cantidad| [trimestre.to_i, cantidad] }
    fila = { motivo: nombres[motivo_id] }
    TRIMESTRES.each { |trimestre| fila[:"t#{trimestre}"] = por_trimestre[trimestre] || 0 }
    fila[:total] = por_trimestre.values.sum
    fila
  end

  def por_tipo
    agrupar_catalogo(:tipo_id, Helic3::Catalogo::Tipo)
  end

  def por_categoria
    agrupar_catalogo(:categoria_id, Helic3::Catalogo::Categoria)
  end

  def por_resultado
    agrupar_catalogo(:resultado_id, Helic3::Catalogo::Resultado)
  end

  def agrupar_catalogo(columna, modelo)
    conteos = pqr_filtradas.group(columna).count
    nombres = modelo.where(id: conteos.keys.compact).pluck(:id, :nombre).to_h
    ordenar_por_cantidad(conteos) { |id| nombres[id] }
  end

  # El responsable es un User nativo de Chatwoot (assignee), no un catalogo de
  # Helic3 -- "Sin asignar" nil, el frontend lo traduce (mismo patron de
  # Garantias N3: nunca texto en español quemado en el backend).
  def por_responsable
    conteos = pqr_filtradas.group(:assignee_id).count
    nombres = User.where(id: conteos.keys.compact).pluck(:id, :name).to_h
    ordenar_por_cantidad(conteos) { |id| nombres[id] }
  end

  def ordenar_por_cantidad(conteos)
    conteos.map { |id, cantidad| { etiqueta: yield(id), cantidad: cantidad } }
           .sort_by { |fila| -fila[:cantidad] }
  end

  FILTROS_DIRECTOS = %i[tipo_id categoria_id motivo_pqr_id assignee_id].freeze

  # cuenta_para_sic excluye las categorias que no generan radicado (p. ej.
  # "Informacion"): una consulta sin radicado no debe inflar ningun conteo.
  # radicada_at nulo significa que el ticket nunca paso por Radicar (un
  # registro manual o de prueba, sin categoria/tipo/motivo tampoco) -- no es
  # una PQR real para este tablero, y sin fecha no se puede ubicar en ningun
  # mes/trimestre. Se excluye aqui, antes de cualquier filtro o agrupacion.
  def pqr_filtradas
    scope = account.tickets.cuenta_para_sic.where.not(radicada_at: nil)
    anio = filtro_entero(:anio)
    mes = filtro_entero(:mes)
    scope = scope.where("EXTRACT(year FROM #{FECHA_LOCAL}) = ?", anio) if anio
    scope = scope.where("EXTRACT(month FROM #{FECHA_LOCAL}) = ?", mes) if mes
    FILTROS_DIRECTOS.reduce(scope) do |acc, columna|
      filtros[columna].present? ? acc.where(columna => filtros[columna]) : acc
    end
  end

  # N1 (revision de Jhan, PR #113, mismo patron aqui): anio/mes no numericos se
  # ignoran en vez de tumbar la consulta con un error de Postgres.
  def filtro_entero(clave)
    Integer(filtros[clave])
  rescue ArgumentError, TypeError
    nil
  end
end
