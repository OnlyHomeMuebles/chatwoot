# Administracion de parametros (ADM-01): Karen edita los tiempos y umbrales del
# modulo (plazos, umbrales del semaforo, autonomia del agente) sin desplegar.
# Lectura para agentes; escritura solo para administradores.
#
# La clave es la llave con la que el dominio lee el parametro: se fija y NO se
# edita. Solo cambian el valor y su unidad. Un valor vacio se rechaza (el dominio
# lee los parametros obligatorios con error explicito, no con un valor por defecto).
class Api::V1::Accounts::Helic3::Admin::ParametrosController < Api::V1::Accounts::BaseController
  # Escritura solo administradores (check_admin_authorization? -> 401). Lectura abierta.
  before_action :check_admin_authorization?, only: [:update]
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

  def parametro_params
    params.require(:parametro).permit(:valor, :unidad)
  end
end
