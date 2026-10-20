# IND-03 (parcial): "Carga de Datos", solo para administradores (criterio del
# Dash CX: "un agente no ve la pestaña Carga de Datos"). Hoy solo el tipo
# 'facturas' tiene parser real -- los otros tres (IND-04) esperan a que se
# sepan sus columnas en el Dash CX.
class Api::V1::Accounts::Helic3::CargasController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    @cargas = Helic3::Carga.where(account: Current.account).order(created_at: :desc)
  end

  def create
    return render_tipo_no_soportado unless params[:tipo] == 'facturas'
    return render_archivo_faltante if params[:archivo].blank?

    @carga = Helic3::Cargas::ImportarFacturas.call(
      account: Current.account, archivo: params[:archivo], modo: params[:modo],
      usuario: Current.user, nombre_archivo: params[:archivo].original_filename
    )
    render :show
  rescue Helic3::Cargas::ImportarFacturas::ColumnasFaltantes => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def render_tipo_no_soportado
    render json: { error: 'tipo de carga no soportado todavia' }, status: :unprocessable_entity
  end

  def render_archivo_faltante
    render json: { error: 'falta el archivo' }, status: :unprocessable_entity
  end
end
