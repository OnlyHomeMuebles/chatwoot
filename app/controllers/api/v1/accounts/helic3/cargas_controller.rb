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
    return render_modo_invalido unless Helic3::Carga::MODOS.include?(params[:modo])

    Helic3::Cargas::ImportarFacturas.verificar_columnas!(params[:archivo])
    @carga = crear_carga_y_encolar
    render :show
  rescue Helic3::Cargas::ImportarFacturas::ColumnasFaltantes => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Borra el registro del historial de la carga. Las facturas que ya haya
  # insertado NO se borran con ella (dependent: :restrict_with_error en el
  # modelo) -- son datos reales del negocio, no se van solo porque se limpie
  # el historial de "quien subio que". Por eso esto solo libera cargas vacias
  # (0 insertadas/actualizadas: un intento fallido, de prueba, o rechazado).
  def destroy
    carga = Helic3::Carga.find_by(account: Current.account, id: params[:id])
    return render_carga_no_encontrada if carga.nil?
    return render_carga_con_facturas unless carga.destroy

    head :no_content
  end

  private

  def crear_carga_y_encolar
    carga = Helic3::Carga.create!(
      account: Current.account, tipo: 'facturas', modo: params[:modo], usuario: Current.user,
      nombre_archivo: params[:archivo].original_filename, estado: 'procesando'
    )
    carga.archivo.attach(params[:archivo])
    Helic3::ImportarFacturasJob.perform_later(carga_id: carga.id)
    carga
  end

  def render_tipo_no_soportado
    render json: { error: 'tipo de carga no soportado todavia' }, status: :unprocessable_entity
  end

  def render_archivo_faltante
    render json: { error: 'falta el archivo' }, status: :unprocessable_entity
  end

  def render_modo_invalido
    render json: { error: 'modo invalido o faltante' }, status: :unprocessable_entity
  end

  def render_carga_no_encontrada
    render json: { error: 'carga no encontrada' }, status: :not_found
  end

  def render_carga_con_facturas
    render json: { error: 'esta carga ya tiene facturas insertadas; no se puede borrar del historial' },
           status: :unprocessable_entity
  end
end
