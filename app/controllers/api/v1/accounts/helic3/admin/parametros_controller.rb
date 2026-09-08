# Administracion de parametros (ADM-01): Karen edita los tiempos y umbrales del
# modulo (plazos, umbrales del semaforo, autonomia del agente) sin desplegar.
# Lectura para agentes; escritura solo para administradores.
#
# La clave es la llave con la que el dominio lee el parametro: se fija y NO se
# edita. Solo cambian el valor y su unidad. Un valor vacio se rechaza (el dominio
# lee los parametros obligatorios con error explicito, no con un valor por defecto).
class Api::V1::Accounts::Helic3::Admin::ParametrosController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator, only: [:update]
  before_action :set_parametro, only: [:update]

  def index
    @parametros = Helic3::Catalogo::Parametro.where(account: Current.account).order(:clave)
  end

  def update
    @parametro.update!(parametro_params)
    render :show
  end

  private

  def set_parametro
    @parametro = Helic3::Catalogo::Parametro.find_by!(account: Current.account, id: params[:id])
  end

  def ensure_administrator
    return if Current.account_user&.administrator?

    render json: { error: I18n.t('helic3.catalogos.solo_admin') }, status: :unauthorized
  end

  def parametro_params
    params.require(:parametro).permit(:valor, :unidad)
  end
end
