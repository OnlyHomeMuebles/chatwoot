# Bandeja de PQR (BAN-01): indice de solo lectura de los expedientes de la cuenta,
# con filtros y paginacion resueltos en SQL. Endpoint propio (no tickets#index)
# porque los dos consumidores piden cosas distintas: el panel de conversacion
# quiere los uno o dos expedientes de ESA conversacion con su reloj derivado; la
# bandeja quiere UNA pagina de la cuenta con filtros y conteos. Mezclarlos
# obligaria a cambiar la forma de la respuesta que el panel ya consume.
#
# El semaforo NO se filtra en SQL (es derivado: dias habiles + festivos). La fila
# expone dias_habiles_restantes (calculo en memoria, sin consulta) y la respuesta
# lleva los umbrales del catalogo una sola vez; el cliente pinta el color con esos
# dos datos, sin duplicar la regla de dias habiles (que vive en el backend).
class Api::V1::Accounts::Helic3::PqrController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :check_authorization

  def index
    filtrados = aplicar_filtros(expedientes_de_la_cuenta)
    @pqr = filtrados.order(created_at: :desc).page(pagina_actual).per(RESULTS_PER_PAGE)
    @total = @pqr.total_count
    @umbrales = umbrales_pqr
    # Decision (VIS-02, resuelta en revision): las metricas SI respetan el mismo
    # filtro que la pagina, no el total de la cuenta. BAN-01 asumia lo contrario
    # (metricas fijas, el filtro solo sobre la tabla); con el tabbar a la vista el
    # usuario entiende que ve un subconjunto, y es la lectura correcta del
    # criterio 1. Van en una consulta aparte de la pagina y sobre un scope limpio
    # (sin includes) para que los conteos no se inflen.
    @metricas = metricas_pqr(aplicar_filtros(Current.account.tickets))
  end

  # Cola de decisiones (DEC-01): lo que el agente propuso y espera a una persona.
  # Ordena por urgencia del reloj legal (las vencidas arriba). Es lo que la hace
  # util. La regla de que exige aprobacion no se escribe aqui: viene de la marca
  # del catalogo (el agente solo guarda la propuesta cuando el resultado la exige).
  def decisiones
    @decisiones = Current.account.tickets
                         .con_decision_pendiente
                         .includes(:categoria, :etapa, conversation: :contact)
                         .order(Arel.sql('plazo_respuesta_vence_at ASC NULLS LAST'))
    @propuestas = propuestas_por_id(@decisiones)
  end

  # Contadores del rail (VIS-05): solo dos numeros con COUNT. NO trae registros ni
  # escribe el estado de la bandeja, y corre en cada carga del dashboard, asi que
  # debe ser barato. Fuente propia justamente para no pisar records/meta de index.
  def contadores
    scope = Current.account.tickets
    render json: {
      sin_responder: scope.where(respondida_at: nil).count,
      decisiones_pendientes: scope.con_decision_pendiente.count
    }
  end

  private

  # Metricas del encabezado (VIS-02): cinco conteos en SQL sobre el scope ya
  # filtrado. Ninguno calcula dias habiles (eso es derivado y caro): "dentro de
  # plazo" y "vencen esta semana" usan la fecha de vencimiento tal cual la columna.
  def metricas_pqr(scope)
    ahora = Time.current
    {
      # radicadas del mes, excluyendo categorias sin radicado (cuenta_para_sic)
      radicadas: scope.cuenta_para_sic.where(created_at: ahora.beginning_of_month..ahora).count,
      # dentro de plazo: respondidas, o con el plazo aun por vencer
      dentro_plazo: scope.where('respondida_at IS NOT NULL OR plazo_respuesta_vence_at >= ?', ahora).count,
      sin_responder: scope.where(respondida_at: nil).count,
      # abren garantia: las que tienen un radicado de garantia colgando
      abren_garantia: scope.joins(:garantia).count,
      # vencen esta semana: sin responder y con el plazo entre hoy y +7 dias
      vencen_semana: scope.where(respondida_at: nil)
                          .where(plazo_respuesta_vence_at: ahora..(ahora + 7.days)).count
    }
  end

  # Precarga los resultados propuestos (uno por expediente, guardado en
  # pqrs_metadata) en una sola consulta, para que la fila no dispare un N+1.
  def propuestas_por_id(decisiones)
    ids = decisiones.filter_map { |t| t.pqrs_metadata['resultado_propuesto_id'] }.uniq
    Helic3::Catalogo::Resultado.where(account: Current.account, id: ids).index_by(&:id)
  end

  # Solo lectura (index y decisiones): se autoriza con index? explicito para no
  # depender del nombre de la accion (Pundit buscaria decisiones?, que no existe).
  # ensure_current_account (base) ya acota a la cuenta; no se reimplementa.
  def check_authorization
    authorize(Helic3::Ticket, :index?)
  end

  # includes de la clasificacion, garantia, datos y el responsable para que la fila
  # no dispare una consulta por expediente. conversation:contact alimenta "cliente";
  # datos alimenta documento y ciudad (VIS-02); garantia alimenta su columna.
  def expedientes_de_la_cuenta
    Current.account.tickets.includes(:categoria, :tipo, :motivo_pqr, :etapa, :datos,
                                     { garantia: { items: :proceso } },
                                     { assignee: { avatar_attachment: :blob } },
                                     { conversation: :contact })
  end

  # Filtros por columna directa: cada uno se aplica solo si viene el parametro.
  FILTROS_DIRECTOS = %i[categoria_id tipo_id etapa_id assignee_id].freeze

  def aplicar_filtros(scope)
    scope = FILTROS_DIRECTOS.reduce(scope) do |acc, columna|
      params[columna].present? ? acc.where(columna => params[columna]) : acc
    end
    scope = filtrar_por_texto(scope)
    scope = solo_sin_responder(scope)
    solo_vencidas(scope)
  end

  # Tab "Sin responder" (VIS-02): sin sello de respuesta. Columna directa, en SQL.
  def solo_sin_responder(scope)
    return scope unless ActiveModel::Type::Boolean.new.cast(params[:sin_responder])

    scope.where(respondida_at: nil)
  end

  # q busca por nombre del cliente, titulo o numero de radicado (el display_id).
  # references(:contacts) para que el LEFT JOIN conviva con el includes de arriba.
  def filtrar_por_texto(scope)
    return scope if params[:q].blank?

    termino = "%#{params[:q].to_s.strip}%"
    scope.left_joins(conversation: :contact)
         .references(:contacts)
         .where('contacts.name ILIKE :q OR helic3_tickets.title ILIKE :q OR ' \
                'CAST(helic3_tickets.display_id AS TEXT) ILIKE :q', q: termino)
  end

  # Vencidas: con plazo pasado y sin responder. Ambas son columnas, se resuelve en SQL.
  def solo_vencidas(scope)
    return scope unless ActiveModel::Type::Boolean.new.cast(params[:vencidas])

    scope.where(respondida_at: nil).where('plazo_respuesta_vence_at < ?', Time.current)
  end

  # Umbrales del semaforo PQR, leidos una sola vez por peticion. Si la cuenta aun
  # no los tiene sembrados, la bandeja no debe caerse: el cliente simplemente no
  # pinta color hasta que se configuren (nil).
  def umbrales_pqr
    Helic3::ParametrosGarantia.desde_catalogo(Current.account, ambito: :pqr)
  rescue Helic3::ParametrosGarantia::ParametroFaltante
    nil
  end

  def pagina_actual
    params[:page].presence || 1
  end
end
