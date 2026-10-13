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

  # sincronizacion perezosa e idempotente (EVI-02, punto 3 del cableado): una
  # escritura durante una lectura, poco elegante pero necesaria porque no se
  # puede registrar un listener de Rails (app/dispatchers/async_dispatcher.rb
  # es upstream). Garantiza que ninguna evidencia se pierda aunque un webhook
  # falle o llegue fuera de orden.
  def show
    sincronizar_evidencias
  end

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
    validar_radicacion_manual!
    Helic3::Ticket.transaction do
      @ticket = Helic3::Casos::Radicar.new(
        account: Current.account,
        titulo: create_params[:title],
        descripcion: create_params[:description],
        conversation_id: conversation_id_de_bd(create_params[:conversation_id]),
        tipo: catalogo_de_cuenta(Helic3::Catalogo::Tipo, create_params[:tipo_id]),
        motivo_pqr: catalogo_de_cuenta(Helic3::Catalogo::MotivoPqr, create_params[:motivo_pqr_id]),
        creator: Current.user,
        numero_orden: create_params[:numero_orden],
        origen: :humano
      ).call
      aplicar_operativos_al_crear
      registrar_detalle_al_crear
      registrar_datos_cliente_al_crear
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

  # best-effort (EVI-02/EVI-03): si un documento puntual falla su validacion,
  # el expediente debe seguir cargando igual -- una evidencia sin sincronizar
  # es un problema de datos, no una pantalla rota. Mismo patron que
  # VincularEvidenciasJob.
  def sincronizar_evidencias
    Helic3::Casos::VincularEvidencias.call(@ticket)
  rescue StandardError => e
    Rails.logger.error("[Helic3] vincular_evidencias (show) ticket=#{@ticket.id}: #{e.class}: #{e.message}")
  end

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

  # VIS-04: el diálogo puede traer un detalle tipificado; se guarda en la ficha con
  # fuente humano (lo eligió el operador), por el mismo servicio que usa el panel
  # (DAT-01). Corre bajo la transaccion del create: si falla, se revierte todo.
  def registrar_detalle_al_crear
    detalle_id = create_params[:detalle_tipificado_id]
    return if detalle_id.blank?

    Helic3::Casos::RegistrarDatos.new(
      ticket: @ticket, campos: { detalle_tipificado_id: detalle_id }, fuente: :humano
    ).call
  end

  # MAN-01: escribe en la ficha los datos del cliente y la compra que llegaron en el
  # bloque `datos`, con fuente humano (lo escribio el operador). Corre bajo la
  # transaccion del create: si falla, se revierte todo (ni ticket, ni ficha, ni
  # evento radicada). RegistrarDatos ignora los vacios y los campos que no conoce.
  def registrar_datos_cliente_al_crear
    campos = datos_cliente_params.to_h.symbolize_keys.compact_blank
    return if campos.blank?

    Helic3::Casos::RegistrarDatos.new(ticket: @ticket, campos: campos, fuente: :humano).call
  end

  # MAN-01: validacion de borde para la radicacion manual. Sin conversacion no hay
  # contacto de Chatwoot de donde sacar el cliente, asi que nombre y telefono son
  # obligatorios (si no, el formato de garantia saldria sin cliente). Con conversacion
  # siguen opcionales: el chat y su panel no cambian. factura_fecha invalida o futura
  # se rechaza (un string invalido la columna date lo guardaria como nil en silencio).
  # Se valida ANTES de abrir la transaccion: si falla, 422 y no se radica nada (CA2).
  # Los errores van sobre :base y no sobre :cliente_nombre/:factura_fecha porque esos
  # NO son atributos de Helic3::Ticket (viven en la ficha): al generar el mensaje,
  # Rails leeria ticket.cliente_nombre y reventaria con NoMethodError -> 500. :base
  # no lee ningun atributo y el mensaje nombra el campo igual (CA2).
  def validar_radicacion_manual!
    errores = Helic3::Ticket.new

    if create_params[:conversation_id].blank?
      datos = datos_cliente_params
      errores.errors.add(:base, 'El nombre del cliente es obligatorio al radicar sin conversacion') if datos[:cliente_nombre].blank?
      errores.errors.add(:base, 'El telefono del cliente es obligatorio al radicar sin conversacion') if datos[:cliente_telefono].blank?
    end

    validar_factura_fecha!(datos_cliente_params[:factura_fecha], errores)

    raise ActiveRecord::RecordInvalid, errores if errores.errors.any?
  end

  # La fecha llega como AAAA-MM-DD (lo que manda un <input type="date">). Un valor
  # no parseable o posterior a hoy es un error del cliente -> 422.
  def validar_factura_fecha!(raw, errores)
    return if raw.blank?

    fecha = begin
      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end

    if fecha.nil?
      errores.errors.add(:base, 'La fecha de compra no es una fecha valida (AAAA-MM-DD)')
    elsif fecha > Date.current
      errores.errors.add(:base, 'La fecha de compra no puede ser una fecha futura')
    end
  end

  # MAN-01: el bloque `datos` del cliente y la compra que el panel escribe a mano.
  # factura_numero NO va aqui (entra por numero_orden y lo guarda Radicar);
  # detalle_tipificado_id tampoco (lo maneja registrar_detalle_al_crear).
  def datos_cliente_params
    @datos_cliente_params ||= params.require(:ticket).fetch(:datos, {}).permit(
      :cedula, :ciudad, :direccion, :producto_nombre,
      :cliente_nombre, :cliente_telefono, :cliente_email,
      :producto_referencia, :factura_fecha
    )
  end

  # Datos de radicacion. NO incluye categoria_id: la categoria la deriva Radicar
  # del motivo, y recibirla abriria una segunda fuente de la misma verdad.
  def create_params
    params.require(:ticket).permit(:title, :description, :conversation_id,
                                   :tipo_id, :motivo_pqr_id, :detalle_tipificado_id,
                                   :status, :assignee_id, :numero_orden)
  end

  # Update solo toca lo operativo: estado y asignacion.
  # resultado_id y etapa_id NO se permiten aqui a proposito (RES-01): resolver es
  # un acto de dominio que sella respondida_at y detiene el reloj legal, y eso solo
  # ocurre por POST /resolucion (Helic3::Casos::Resolver). Si se pudiera escribir
  # resultado_id por un update, el reloj se detendria sin que nadie haya respondido:
  # dos puertas a la misma verdad terminan contandola distinto.
  # Corregir la clasificacion ya radicada (tipo/motivo/categoria) tambien queda
  # fuera: cambiaria la categoria y el plazo sin re-derivarlos (decision de negocio).
  def update_params
    params.require(:ticket).permit(:status, :assignee_id)
  end
end
