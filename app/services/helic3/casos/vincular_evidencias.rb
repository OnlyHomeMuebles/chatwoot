# EVI-01: sincroniza los documentos de un expediente desde los adjuntos de su
# conversacion. Se llama desde varios puntos (EVI-02: al radicar, al llegar un
# mensaje, al leer el expediente) porque no se puede registrar un listener de
# Rails (app/dispatchers/async_dispatcher.rb es upstream); por eso es
# idempotente por diseno y la garantia real la da el indice unico parcial de
# la migracion, no este chequeo en memoria (que solo evita trabajo repetido).
class Helic3::Casos::VincularEvidencias
  def self.call(ticket)
    new(ticket).call
  end

  def initialize(ticket)
    @ticket = ticket
  end

  def call
    conversation = @ticket.conversation
    return [] if conversation.nil?

    ids_existentes = @ticket.documentos.where.not(attachment_id: nil).pluck(:attachment_id)
    mensajes_con_adjuntos(conversation).flat_map { |mensaje| vincular_adjuntos(mensaje, ids_existentes) }
  end

  private

  # El filtro (que tenga adjuntos) corre en SQL, sin cargar toda la
  # conversacion en memoria; el preload va en una consulta aparte porque
  # combinar :attachments (el joins) con :sender (polimorfica) en el mismo
  # includes fuerza un eager_load que revienta contra una asociacion polimorfica.
  def mensajes_con_adjuntos(conversation)
    # reorder(nil): Message tiene un default_scope por created_at que Postgres
    # exige incluir en el SELECT cuando se combina con DISTINCT; aqui el orden
    # no importa (solo se usa para filtrar ids).
    ids = conversation.messages.joins(:attachments).distinct.reorder(nil).pluck(:id)
    Message.where(id: ids).includes(:attachments, :sender)
  end

  def vincular_adjuntos(mensaje, ids_existentes)
    mensaje.attachments.filter_map do |adjunto|
      vincular(mensaje, adjunto) unless ids_existentes.include?(adjunto.id)
    end
  end

  def vincular(mensaje, adjunto)
    # requires_new: true es obligatorio: VincularEvidencias corre a veces
    # DENTRO de la transaccion de Radicar (el barrido hacia atras). Sin
    # savepoint propio, una violacion del indice unico deja envenenada la
    # transaccion externa completa aunque el rescue atrape la excepcion aqui
    # -- Postgres ignora cualquier sentencia posterior hasta el rollback.
    Helic3::Documento.transaction(requires_new: true) do
      documento = Helic3::Documento.create!(
        account: @ticket.account, ticket: @ticket, attachment: adjunto, message: mensaje,
        clase: 'evidencia', origen: origen_del_mensaje(mensaje),
        remitente_nombre: mensaje.sender&.name,
        remitente_user: (mensaje.sender if mensaje.sender.is_a?(User)),
        ocurrido_at: mensaje.created_at, titulo: adjunto.file.filename.to_s
      )
      Helic3::Evento.registrar!(
        ticket: @ticket, tipo: 'evidencia_adjuntada', origen: origen_del_evento(mensaje),
        payload: { 'documento_id' => documento.id, 'titulo' => documento.titulo }
      )
      documento
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # entrante => cliente; saliente con remitente User => operador; saliente
  # sin remitente => agente (el bot HELIC3 no es un User del sistema).
  def origen_del_mensaje(mensaje)
    return 'cliente' if mensaje.incoming?
    return 'operador' if mensaje.sender.is_a?(User)

    'agente'
  end

  # Helic3::Evento solo distingue humano/agente (ver Evento::ORIGENES);
  # cliente y operador son ambos personas desde el punto de vista de la bitacora.
  def origen_del_evento(mensaje)
    origen_del_mensaje(mensaje) == 'agente' ? 'agente' : 'humano'
  end
end
