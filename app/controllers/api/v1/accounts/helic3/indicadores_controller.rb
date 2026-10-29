# IND-01: endpoint de solo lectura para la seccion "Indicadores" (garantias y
# PQR por mes, trimestre, motivo, detalle, producto, ciudad y responsable).
# Mismo criterio de autorizacion que PqrController: index? es true para
# cualquier agente de la cuenta, la restriccion de la pestana Carga de Datos
# (solo administradores) llega con IND-03.
class Api::V1::Accounts::Helic3::IndicadoresController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def garantias
    @indicadores = Helic3::Indicadores::Garantias.call(account: Current.account, filtros: filtros_garantias)
  end

  def pqr
    @indicadores = Helic3::Indicadores::Pqr.call(account: Current.account, filtros: filtros_pqr)
  end

  # Resumen "Todas las PQR" (mockup v12): Garantias + Derechos de Peticion
  # juntos, solo anio/mes como filtro compartido.
  def todas
    @indicadores = Helic3::Indicadores::Todas.call(account: Current.account, filtros: filtros_todas)
  end

  # IND-06: Devolucion, expediente hermano de Garantia (ver
  # Helic3::Indicadores::Devoluciones).
  def devoluciones
    @indicadores = Helic3::Indicadores::Devoluciones.call(account: Current.account, filtros: filtros_devoluciones)
  end

  # Detalle de clientes y casos (mockup v12): paginado y ordenado por urgencia,
  # con los mismos filtros de #garantias -- se pide aparte porque, a
  # diferencia de los agregados de #garantias, no tiene sentido recalcularlo
  # en cada filtro si lo unico que cambio fue la pagina.
  def garantias_casos
    servicio = Helic3::Indicadores::Garantias.new(account: Current.account, filtros: filtros_garantias)
    @casos = servicio.casos(pagina: params[:pagina])
  end

  def devoluciones_casos
    servicio = Helic3::Indicadores::Devoluciones.new(account: Current.account, filtros: filtros_devoluciones)
    @casos = servicio.casos(pagina: params[:pagina])
  end

  # IND-05: la misma tabla que se esta viendo en pantalla, con los mismos
  # filtros, descargada en CSV. Nunca se calcula nada que la tabla no muestre
  # ya -- esto solo reempaqueta la respuesta de los servicios existentes.
  SECCIONES_GARANTIAS = %w[mensual trimestral por_ciudad por_motivo por_detalle por_proceso por_producto].freeze

  def garantias_csv
    return render_seccion_invalida unless SECCIONES_GARANTIAS.include?(params[:seccion])

    datos = Helic3::Indicadores::Garantias.call(account: Current.account, filtros: filtros_garantias)
    enviar_csv("indicadores-garantias-#{params[:seccion]}", *filas_garantias(datos, params[:seccion]))
  end

  SECCIONES_PQR = %w[mensual trimestral motivo_por_trimestre por_tipo por_categoria por_resultado
                     por_responsable].freeze

  def pqr_csv
    return render_seccion_invalida unless SECCIONES_PQR.include?(params[:seccion])

    datos = Helic3::Indicadores::Pqr.call(account: Current.account, filtros: filtros_pqr)
    enviar_csv("indicadores-pqr-#{params[:seccion]}", *filas_pqr(datos, params[:seccion]))
  end

  SECCIONES_DEVOLUCIONES = %w[mensual trimestral por_ciudad por_motivo por_detalle por_proceso por_producto].freeze

  def devoluciones_csv
    return render_seccion_invalida unless SECCIONES_DEVOLUCIONES.include?(params[:seccion])

    datos = Helic3::Indicadores::Devoluciones.call(account: Current.account, filtros: filtros_devoluciones)
    enviar_csv("indicadores-devoluciones-#{params[:seccion]}", *filas_devoluciones(datos, params[:seccion]))
  end

  private

  def check_authorization
    authorize(Helic3::Ticket, :index?)
  end

  FILTROS_GARANTIAS = %i[anio mes cobertura_ciudad_id motivo_garantia_id detalle_tipificado_id proceso_id
                         producto].freeze

  def filtros_garantias
    params.permit(*FILTROS_GARANTIAS).to_h.symbolize_keys
  end

  FILTROS_PQR = %i[anio mes tipo_id categoria_id motivo_pqr_id assignee_id].freeze

  def filtros_pqr
    params.permit(*FILTROS_PQR).to_h.symbolize_keys
  end

  FILTROS_TODAS = %i[anio mes].freeze

  def filtros_todas
    params.permit(*FILTROS_TODAS).to_h.symbolize_keys
  end

  FILTROS_DEVOLUCIONES = %i[anio mes cobertura_ciudad_id motivo_devolucion_id detalle_tipificado_id proceso_id
                            producto].freeze

  def filtros_devoluciones
    params.permit(*FILTROS_DEVOLUCIONES).to_h.symbolize_keys
  end

  def render_seccion_invalida
    render json: { error: 'seccion invalida o faltante' }, status: :unprocessable_entity
  end

  # "Sin ciudad"/"Sin tipo"/etc. aqui SI van quemados en español (a diferencia
  # del JSON de #garantias/#pqr, que devuelve nil a proposito para que el
  # frontend traduzca): un CSV no tiene capa de i18n, y el texto debe ser
  # identico al que ya ve Karen en la tabla en pantalla.
  FALLBACK_ETIQUETA = {
    'por_ciudad' => 'Sin ciudad',
    'por_motivo' => 'Sin motivo',
    'por_detalle' => 'Sin detalle',
    'por_proceso' => 'Sin etapa',
    'por_tipo' => 'Sin tipo',
    'por_categoria' => 'Sin categoría',
    'por_resultado' => 'Sin resultado',
    'por_responsable' => 'Sin asignar'
  }.freeze

  def filas_garantias(datos, seccion)
    filas_radicado_periodo(datos, seccion, 'Garantías')
  end

  def filas_devoluciones(datos, seccion)
    filas_radicado_periodo(datos, seccion, 'Devoluciones')
  end

  # mensual/trimestral de Garantias y Devoluciones tienen la misma forma
  # (periodo, cantidad, solucionadas, en_proceso) -- solo cambia el nombre de
  # la columna de cantidad.
  def filas_radicado_periodo(datos, seccion, etiqueta_cantidad)
    case seccion
    when 'mensual', 'trimestral'
      periodo_encabezado = seccion == 'mensual' ? 'Mes' : 'Trimestre'
      filas = datos[seccion.to_sym].map { |f| [f[:periodo], f[:cantidad], f[:solucionadas], f[:en_proceso]] }
      [[periodo_encabezado, etiqueta_cantidad, 'Solucionadas', 'En proceso'], filas]
    else
      filas_etiqueta_cantidad(datos[seccion.to_sym], seccion)
    end
  end

  def filas_pqr(datos, seccion)
    case seccion
    when 'mensual', 'trimestral'
      periodo_encabezado = seccion == 'mensual' ? 'Mes' : 'Trimestre'
      filas = datos[seccion.to_sym].map { |f| [f[:periodo], f[:cantidad], f[:respondidas], f[:pendientes]] }
      [[periodo_encabezado, 'PQR', 'Respondidas', 'Pendientes'], filas]
    when 'motivo_por_trimestre'
      filas = datos[:motivo_por_trimestre].map do |f|
        [f[:motivo] || FALLBACK_ETIQUETA['por_motivo'], f[:t1], f[:t2], f[:t3], f[:t4], f[:total]]
      end
      [%w[Motivo T1 T2 T3 T4 Total], filas]
    else
      filas_etiqueta_cantidad(datos[seccion.to_sym], seccion)
    end
  end

  def filas_etiqueta_cantidad(registros, seccion)
    filas = registros.map { |f| [f[:etiqueta] || FALLBACK_ETIQUETA[seccion], f[:cantidad]] }
    [%w[Etiqueta Cantidad], filas]
  end

  # BOM + ';' para que el Excel en español de Colombia abra tildes y columnas
  # sin pedir el asistente de importacion (su separador de columnas regional
  # es ';', no ',', porque la coma ya es el separador decimal).
  def enviar_csv(nombre, encabezados, filas)
    csv = CSVSafe.generate(col_sep: ';') do |tabla|
      tabla << encabezados
      filas.each { |fila| tabla << fila.map { |valor| formatear_csv(valor) } }
    end
    bom = "\xEF\xBB\xBF"
    nombre_archivo = "#{nombre}-#{Date.current.strftime('%Y-%m')}.csv"
    send_data "#{bom}#{csv}", filename: nombre_archivo, type: 'text/csv'
  end

  # Los porcentajes (cuando IND-03 los sume) deben salir con coma decimal,
  # como espera el Excel en español -- un punto decimal se leeria como
  # separador de miles y da un numero 1000x mas grande al abrir.
  def formatear_csv(valor)
    valor.is_a?(Float) ? valor.to_s.tr('.', ',') : valor
  end
end
