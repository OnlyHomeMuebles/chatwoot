class Api::V1::Accounts::Helic3::AgentesController < Api::V1::Accounts::BaseController
  # H3A-05: CRUD de agentes del panel de Agentes IA. Todo el CRUD es solo para
  # administradores (check_admin_authorization? -> 401/403). El `catalogo` (H3A-03)
  # queda abierto como lectura, igual que el resto de catalogos del modulo.
  before_action :check_admin_authorization?, except: [:catalogo]
  before_action :set_agente, only: [:show, :update, :destroy, :toggle]
  before_action :validar_team, only: [:create, :update]

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

  # codigo es inmutable tras crear: identifica al agente en el runner y en los
  # handoffs; cambiarlo le quitaria su seccion contextual (pqrs/logistica/...).
  def update
    return render_bloqueo_de_sistema if intento_de_pausar_sistema?

    @agente.update!(agente_params.except(:inbox_ids, :codigo))
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
  # El agente de sistema (el triage) no se puede pausar: es el hub de ruteo, y sin
  # el la orquesta se queda sin punto de entrada.
  def toggle
    return render_bloqueo_de_sistema if @agente.es_sistema? && @agente.activo?

    @agente.update!(activo: !@agente.activo)
    render :show
  end

  private

  def render_bloqueo_de_sistema
    render json: { message: 'El agente de sistema (recepción) no se puede eliminar ni pausar' },
           status: :unprocessable_entity
  end

  # ¿el update intenta apagar al agente de sistema? (activo=false explicito)
  def intento_de_pausar_sistema?
    return false unless @agente.es_sistema?

    valor = agente_params[:activo]
    !valor.nil? && !ActiveModel::Type::Boolean.new.cast(valor)
  end

  # team_id, si viene, debe ser de la cuenta actual (evita fugas entre cuentas)
  def validar_team
    team_id = params.dig(:agente, :team_id)
    return if team_id.blank? || Current.account.teams.exists?(id: team_id)

    render json: { message: 'El equipo no pertenece a esta cuenta' }, status: :unprocessable_entity
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
