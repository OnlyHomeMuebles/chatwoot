class Api::V1::Accounts::Helic3::TicketsController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket, only: [:show, :update, :destroy, :assign]
  before_action :check_authorization

  def index
    @tickets = apply_filters(
      Current.account.tickets
             .includes(:assignee, :creator, :categoria, :tipo, :motivo_pqr, :resultado, :etapa, :conversation)
             .latest
    )
  end

  def show; end

  # Nace por Helic3::Casos::Radicar (CAS-01): la unica puerta de radicacion, para
  # que un expediente creado desde el panel arranque con su reloj corriendo igual
  # que uno creado por el agente. La categoria la deriva el servicio del motivo;
  # no se envia desde aqui.
  #
  # Todo en UNA transaccion: Radicar abre la suya, pero al anidarla dentro de esta
  # los operativos (status/assignee) quedan en el mismo alcance. Si su update! falla,
  # se revierte tambien la radicacion — nunca queda un expediente huerfano con numero
  # y reloj legal corriendo que nadie atenderia. No se rescata aqui: la excepcion
  # debe salir de la transaccion para que haya rollback (el rescue_from base responde).
  def create
    Helic3::Ticket.transaction do
      @ticket = Helic3::Casos::Radicar.new(
        account: Current.account,
        titulo: create_params[:title],
        descripcion: create_params[:description],
        conversation_id: conversation_id_de_bd(create_params[:conversation_id]),
        tipo: catalogo_de_cuenta(Helic3::Catalogo::Tipo, create_params[:tipo_id]),
        motivo_pqr: catalogo_de_cuenta(Helic3::Catalogo::MotivoPqr, create_params[:motivo_pqr_id]),
        creator: Current.user,
        origen: :humano
      ).call
      aplicar_operativos_al_crear
    end
  end

  def update
    @ticket.update!(update_params)
  end

  def destroy
    @ticket.destroy!
    head :ok
  end

  def assign
    assignee = params[:assignee_id].present? ? Current.account.users.find(params[:assignee_id]) : nil
    @ticket.update!(assignee: assignee)
    render :show
  end

  private

  def apply_filters(scope)
    scope = filter_by_status(scope)
    scope = scope.assigned_to(Current.user) if params[:mine].present?
    scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    scope = scope.where(conversation_id: conversation_id_de_bd(params[:conversation_id])) if params[:conversation_id].present?
    scope
  end

  # El frontend habla en display_id (el id publico de la API de Chatwoot, que el
  # serializador de conversaciones expone bajo el nombre "id"); el dominio guarda
  # el id de base de datos. La traduccion vive AQUI, en el borde, una sola vez —
  # igual que la tool del agente (radicar_pqr_tool). Radicar sigue recibiendo el id
  # de BD y no cambia: traducir es responsabilidad de la frontera, no del dominio.
  #
  # Se resuelve SIEMPRE contra la cuenta actual: una conversacion inexistente o de
  # otra cuenta levanta RecordNotFound (404 "Resource could not be found"), no el
  # error de validacion del modelo sobre cuentas, que al operador no le dice nada.
  def conversation_id_de_bd(display_id)
    return if display_id.blank?

    Current.account.conversations.find_by!(display_id: display_id).id
  end

  def filter_by_status(scope)
    return scope unless params[:status].present? && Helic3::Ticket.statuses.key?(params[:status])

    scope.where(status: params[:status])
  end

  # authorize the record when we have one so the policy can apply
  # per-ticket rules (e.g. agents deleting their own tickets)
  def check_authorization
    @ticket.present? ? authorize(@ticket) : authorize(Helic3::Ticket)
  end

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:id])
  end

  # Resuelve un catalogo por id acotado a la cuenta: un id de otra cuenta no
  # existe aqui y se rechaza (RecordNotFound). Nulo cuando no se envio.
  def catalogo_de_cuenta(modelo, id)
    return if id.blank?

    modelo.find_by!(account: Current.account, id: id)
  end

  # status/assignee_id no son parte de la firma de Radicar; se aplican dentro de la
  # transaccion del create, sin silenciar lo que el panel pida al crear (ni tocar
  # el servicio). Corre bajo la transaccion: si algo falla, se revierte todo.
  def aplicar_operativos_al_crear
    operativos = create_params.slice(:status, :assignee_id).compact_blank
    return if operativos.blank?

    validar_status!(operativos[:status])
    @ticket.update!(operativos)
  end

  # Un status fuera del enum es un dato del cliente: se rechaza con 422 (via
  # RecordInvalid), no con el ArgumentError -> 500 que levantaria la asignacion
  # del enum. Se valida antes de update! para no depender de ese comportamiento.
  def validar_status!(status)
    return if status.blank? || Helic3::Ticket.statuses.key?(status)

    @ticket.errors.add(:status, :inclusion, value: status)
    raise ActiveRecord::RecordInvalid, @ticket
  end

  # Datos de radicacion. NO incluye categoria_id: la categoria la deriva Radicar
  # del motivo, y recibirla abriria una segunda fuente de la misma verdad.
  def create_params
    params.require(:ticket).permit(:title, :description, :conversation_id,
                                   :tipo_id, :motivo_pqr_id, :status, :assignee_id)
  end

  # Update solo toca lo operativo: estado, asignacion y avance de etapa/resultado.
  # Corregir la clasificacion ya radicada (tipo/motivo/categoria) queda fuera:
  # cambiaria la categoria y el plazo sin re-derivarlos (decision de negocio).
  def update_params
    params.require(:ticket).permit(:status, :assignee_id, :etapa_id, :resultado_id)
  end
end
