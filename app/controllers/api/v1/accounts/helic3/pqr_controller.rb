# Bandeja de PQR (BAN-01): indice de solo lectura de los expedientes de la cuenta,
# con filtros y paginacion resueltos en SQL. Endpoint propio (no tickets#index)
# porque los dos consumidores piden cosas distintas: el panel de conversacion
# quiere los uno o dos expedientes de ESA conversacion con su reloj derivado; la
# bandeja quiere UNA pagina de la cuenta con filtros y conteos. Mezclarlos
# obligaria a cambiar la forma de la respuesta que el panel ya consume.
#
# El semaforo NO se filtra ni se calcula aqui: es derivado (dias habiles + festivos)
# y costaria por fila. Se expone plazo_respuesta_vence_at y el cliente pinta el
# color con los umbrales del catalogo — la misma regla, una sola vez.
class Api::V1::Accounts::Helic3::PqrController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :check_authorization

  def index
    filtrados = aplicar_filtros(expedientes_de_la_cuenta)
    @pqr = filtrados.order(created_at: :desc).page(pagina_actual).per(RESULTS_PER_PAGE)
    @total = @pqr.total_count
  end

  private

  # Solo lectura, pero se autoriza igual que el resto del modulo para acotar por
  # politica. ensure_current_account (base) ya acota a la cuenta; no se reimplementa.
  def check_authorization
    authorize(Helic3::Ticket)
  end

  # includes de la clasificacion y el responsable para que la fila no dispare una
  # consulta por expediente. conversation:contact alimenta la columna "cliente".
  def expedientes_de_la_cuenta
    Current.account.tickets.includes(:assignee, :categoria, :tipo, :motivo_pqr, :etapa,
                                     conversation: :contact)
  end

  # Filtros por columna directa: cada uno se aplica solo si viene el parametro.
  FILTROS_DIRECTOS = %i[categoria_id tipo_id etapa_id assignee_id].freeze

  def aplicar_filtros(scope)
    scope = FILTROS_DIRECTOS.reduce(scope) do |acc, columna|
      params[columna].present? ? acc.where(columna => params[columna]) : acc
    end
    scope = filtrar_por_texto(scope)
    solo_vencidas(scope)
  end

  # q busca por nombre del cliente, titulo o numero de radicado (el display_id).
  def filtrar_por_texto(scope)
    return scope if params[:q].blank?

    termino = "%#{params[:q].to_s.strip}%"
    scope.left_joins(conversation: :contact)
         .where('contacts.name ILIKE :q OR helic3_tickets.title ILIKE :q OR ' \
                'CAST(helic3_tickets.display_id AS TEXT) ILIKE :q', q: termino)
  end

  # Vencidas: con plazo pasado y sin responder. Ambas son columnas, se resuelve en SQL.
  def solo_vencidas(scope)
    return scope unless ActiveModel::Type::Boolean.new.cast(params[:vencidas])

    scope.where(respondida_at: nil).where('plazo_respuesta_vence_at < ?', Time.current)
  end

  def pagina_actual
    params[:page].presence || 1
  end
end
