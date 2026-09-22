class Api::V1::Accounts::Helic3::AgentesController < Api::V1::Accounts::BaseController
  # H3A-05: CRUD de agentes del panel de Agentes IA. Todo el CRUD es solo para
  # administradores (check_admin_authorization? -> 401/403). El `catalogo` (H3A-03)
  # queda abierto como lectura, igual que el resto de catalogos del modulo.
  before_action :check_admin_authorization?, except: [:catalogo]
  before_action :set_agente, only: [:show, :update, :destroy, :toggle]

  # H3A-03: catalogo FIJO de solo lectura. Las herramientas disponibles y el texto
  # de las reglas duras viven en codigo; se exponen aqui para que el panel (H3A-14)
  # no los duplique. Agregar una herramienta en el catalogo la hace aparecer aqui
  # sin tocar el front. Las reglas duras son el bloque real de CoreRules (decision 2).
  def catalogo
    render json: {
      herramientas: Helic3::Agents::CatalogoHerramientas.para_api,
      reglas_duras: Helic3::Agents::PromptBuilder.reglas_duras
    }
  end

  def index
    @agentes = agentes_de_la_cuenta.order(:es_sistema, :codigo)
  end

  def show; end

  def create
    @agente = agentes_de_la_cuenta.new(agente_params.except(:inbox_ids))
    @agente.creado_por = Current.user
    @agente.save!
    sincronizar_bandejas!(@agente)
    render :show, status: :created
  end

  def update
    @agente.update!(agente_params.except(:inbox_ids))
    sincronizar_bandejas!(@agente)
    render :show
  end

  # destroy bloqueado cuando es_sistema (crit 3). El modelo tambien lo protege
  # (before_destroy), pero aqui se devuelve un 422 claro en vez de un fallo opaco.
  def destroy
    return render_bloqueo_de_sistema if @agente.es_sistema?

    @agente.destroy!
    head :ok
  end

  # prende/apaga el agente sin editar el resto (pausar/reactivar desde el panel).
  def toggle
    @agente.update!(activo: !@agente.activo)
    render :show
  end

  private

  def render_bloqueo_de_sistema
    render json: { message: 'Un agente de sistema no se puede eliminar' }, status: :unprocessable_entity
  end

  # scope por cuenta: un agente de otra cuenta no aparece aqui, asi que set_agente
  # levanta RecordNotFound -> 404 (no 403), como pide el crit 1.
  def agentes_de_la_cuenta
    Helic3::Agente.where(account: Current.account).includes(agente_bandejas: :inbox)
  end

  def set_agente
    @agente = agentes_de_la_cuenta.find(params[:id])
  end

  def agente_params
    params.require(:agente).permit(
      :codigo, :nombre, :descripcion, :criterio_ruteo, :prompt, :tono, :modelo, :horario,
      :confianza_minima, :max_respuestas, :team_id, :mensaje_handoff, :activo, :politicas_texto,
      herramientas: [], inbox_ids: []
    )
  end

  # Sincroniza las bandejas del agente con inbox_ids (solo inboxes de la cuenta).
  # Si no viene inbox_ids en la peticion, no toca las bandejas actuales.
  def sincronizar_bandejas!(agente)
    ids = agente_params[:inbox_ids]
    return if ids.nil?

    validos = Current.account.inboxes.where(id: ids).pluck(:id)
    agente.agente_bandejas.where.not(inbox_id: validos).destroy_all
    (validos - agente.agente_bandejas.pluck(:inbox_id)).each do |inbox_id|
      agente.agente_bandejas.create!(inbox_id: inbox_id)
    end
  end
end
