class Api::V1::Accounts::Helic3::ResolucionesController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # Un resultado que abre garantia sin ciudad ni productos no puede radicar un
  # expediente vacio: Resolver levanta ArgumentError (dominio puro, no sabe de
  # HTTP) y aqui se traduce a 422 comprensible.
  rescue_from ArgumentError, with: :render_argument_error

  # POST /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/resolucion
  #
  # La UNICA puerta para registrar el resultado de una PQR. Delega en
  # Helic3::Casos::Resolver (RES-01): no hay logica de resolucion aqui, solo
  # traduccion — se resuelve el resultado contra la cuenta y se llama al servicio.
  # Endpoint propio (no update) porque resolver es un acto de dominio con reloj
  # legal, no una edicion de campos sueltos.
  def create
    resultado = resultado_de_cuenta
    # segunda puerta: la general (participante del expediente) ya paso en
    # check_authorization; aqui se pregunta si ESTE resultado exige admin.
    authorize(resultado, :aplicar?)

    @ticket = Helic3::Casos::Resolver.new(
      ticket: @ticket,
      resultado: resultado,
      actor: Current.user,
      origen: :humano,
      garantia: datos_garantia
    ).call
    render 'api/v1/accounts/helic3/tickets/show', formats: [:json]
  end

  private

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:ticket_id])
  end

  # Bloque opcional de garantia (GAR-02): nil si no viene. El controlador traduce
  # ids -> objetos de la cuenta (un id ajeno no existe aqui: 404), igual que con
  # el resultado. Resolver solo lo usa cuando el resultado abre garantia.
  def datos_garantia
    bloque = params[:garantia]
    return if bloque.blank?

    {
      cobertura_ciudad: catalogo_de_cuenta(Helic3::Catalogo::CoberturaCiudad, bloque[:cobertura_ciudad_id]),
      items: Array(bloque[:items]).map { |item| item_de_garantia(item) }
    }
  end

  def item_de_garantia(item)
    {
      producto_nombre: item[:producto_nombre],
      producto_referencia: item[:producto_referencia],
      motivo_garantia: catalogo_de_cuenta(Helic3::Catalogo::MotivoGarantia, item[:motivo_garantia_id]),
      detalle_tipificado: catalogo_de_cuenta(Helic3::Catalogo::DetalleTipificado, item[:detalle_tipificado_id])
    }
  end

  # id acotado a la cuenta: un id de otra cuenta no existe aqui (404). Nil si no vino.
  def catalogo_de_cuenta(modelo, id)
    return if id.blank?

    modelo.find_by!(account: Current.account, id: id)
  end

  def render_argument_error(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  # puerta general: quien puede tocar este expediente (TicketPolicy#resolver? =
  # admin o participante). Se nombra la accion explicitamente, si no Pundit
  # deduciria create? (que es true para todos). El limite fino por resultado
  # (requiere_admin) corre en #create, ya con el resultado cargado.
  def check_authorization
    authorize(@ticket, :resolver?)
  end

  # Un resultado inexistente o de otra cuenta no existe aqui: RecordNotFound (404),
  # nunca el error de validacion del modelo sobre cuentas.
  def resultado_de_cuenta
    Helic3::Catalogo::Resultado.find_by!(account: Current.account, id: params.require(:resultado_id))
  end
end
