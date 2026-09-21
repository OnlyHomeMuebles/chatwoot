# frozen_string_literal: true

# Decides whether an incoming Chatwoot webhook should trigger the Only Home agent system, and
# enqueues processing tied to the Chatwoot conversation. Only reacts to public incoming messages
# (customer messages), and is idempotent against webhook retries via a short-lived Redis key on
# the message id.
class Helic3::WebhookHandler
  IDEMPOTENCY_TTL = 1.hour.to_i

  def initialize(payload)
    @payload = payload.to_h.with_indifferent_access
  end

  def process
    return unless incoming_message?
    return unless bot_should_handle?
    return unless first_delivery?

    Helic3::ProcessConversationJob.perform_later(
      account_id: account_id,
      conversation_id: conversation_display_id,
      content: content,
      imagenes: imagenes
    )
  end

  private

  # Un mensaje sin texto pero con foto (el caso normal de "aquí está el daño") ya
  # no se descarta: content.present? por si solo dejaba pasar mensajes vacios
  # sin adjuntos. imagenes.present? cubre la foto sola.
  def incoming_message?
    @payload[:event] == 'message_created' &&
      @payload[:message_type] == 'incoming' &&
      !ActiveModel::Type::Boolean.new.cast(@payload[:private]) &&
      (content.present? || imagenes.present?) &&
      conversation_display_id.present?
  end

  # El bot solo atiende conversaciones en estado 'pending' (territorio del bot). Cuando se escala a
  # un humano o se resuelve, el estado pasa a 'open'/'resolved' y el bot debe quedarse callado para
  # no pisar al agente humano. Si el estado no viene en el payload, se asume territorio del bot.
  def bot_should_handle?
    status = @payload.dig(:conversation, :status)
    status.blank? || status == 'pending'
  end

  # Redis SET NX returns "OK" only the first time; nil on webhook retries with the same message id.
  def first_delivery?
    Redis::Alfred.set("helic3:webhook:message:#{@payload[:id]}", 1, nx: true, ex: IDEMPOTENCY_TTL).present?
  end

  def content
    @payload[:content]
  end

  # Fotos del mensaje entrante (Message#webhook_data ya las trae con su URL:
  # push_event_data de un adjunto tipo imagen incluye data_url). Solo imagenes: un
  # audio o un PDF no le sirven de nada a analizar_imagen.
  def imagenes
    Array(@payload[:attachments]).filter_map do |adjunto|
      adjunto[:data_url] if adjunto[:file_type].to_s == 'image' && adjunto[:data_url].present?
    end
  end

  def conversation_display_id
    @payload.dig(:conversation, :id)
  end

  def account_id
    @payload.dig(:conversation, :account_id) || @payload.dig(:account, :id)
  end
end
