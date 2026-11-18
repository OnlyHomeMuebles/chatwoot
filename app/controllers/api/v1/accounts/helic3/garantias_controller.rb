class Api::V1::Accounts::Helic3::GarantiasController < Api::V1::Accounts::BaseController
  before_action :fetch_garantia
  before_action :check_authorization

  # PATCH /api/v1/accounts/:account_id/helic3/garantias/:id/observacion
  #
  # GAR-08: anexa o corrige la observacion de una garantia YA cerrada. La
  # observacion del cierre normal se exige en el MISMO movimiento que cierra
  # (garantia_items#update); este endpoint cubre los dos casos tardios:
  #   - figura 3: garantias cerradas antes del despliegue, sin observacion.
  #   - figura 2: editar una observacion ya puesta.
  # Texto obligatorio; registra el evento garantia_finalizada (editar vuelve a
  # registrarlo con el texto nuevo) y responde el expediente.
  def observacion
    return render_error('La garantia aun no esta cerrada') unless @garantia.cerrada?

    texto = params[:observacion].to_s.strip
    return render_error('La observacion de cierre es obligatoria') if texto.blank?

    @garantia.anexar_observacion_cierre!(texto, Current.user)
    Helic3::Evento.registrar!(ticket: @garantia.ticket, tipo: 'garantia_finalizada',
                              origen: 'humano', actor: Current.user, garantia: @garantia,
                              payload: { observacion: texto })
    @ticket = @garantia.ticket
    render 'api/v1/accounts/helic3/tickets/show', formats: [:json]
  end

  private

  # una garantia de otra cuenta no existe aqui: RecordNotFound (404), igual que
  # el item en garantia_items.
  def fetch_garantia
    @garantia = Helic3::Garantia.find_by!(account: Current.account, id: params[:id])
  end

  # anexar la observacion es un acto operativo sobre el expediente: lo puede hacer
  # quien participa de el, como avanzar un producto (misma regla que garantia_items).
  def check_authorization
    authorize(@garantia.ticket, :update?)
  end

  def render_error(mensaje)
    render json: { error: mensaje }, status: :unprocessable_entity
  end
end
