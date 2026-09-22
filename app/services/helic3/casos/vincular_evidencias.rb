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

  def mensajes_con_adjuntos(conversation)
    conversation.messages.includes(:attachments, :sender).select { |mensaje| mensaje.attachments.any? }
  end

  def vincular_adjuntos(mensaje, ids_existentes)
    mensaje.attachments.filter_map do |adjunto|
      vincular(mensaje, adjunto) unless ids_existentes.include?(adjunto.id)
    end
  end

  def vincular(mensaje, adjunto)
    Helic3::Documento.transaction do
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
