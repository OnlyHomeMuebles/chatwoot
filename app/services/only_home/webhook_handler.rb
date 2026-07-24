# frozen_string_literal: true

# Decides whether an incoming Chatwoot webhook should trigger the Only Home agent system, and
# enqueues processing tied to the Chatwoot conversation. Only reacts to public incoming messages
# (customer messages), and is idempotent against webhook retries via a short-lived Redis key on
# the message id.
class OnlyHome::WebhookHandler
  IDEMPOTENCY_TTL = 1.hour.to_i

  def initialize(payload)
    @payload = payload.to_h.with_indifferent_access
  end

  def process
    return unless incoming_message?
    return unless first_delivery?

    OnlyHome::ProcessConversationJob.perform_later(
      account_id: account_id,
      conversation_id: conversation_display_id,
      content: content
    )
  end

  private

  def incoming_message?
    @payload[:event] == 'message_created' &&
      @payload[:message_type] == 'incoming' &&
      !ActiveModel::Type::Boolean.new.cast(@payload[:private]) &&
      content.present? &&
      conversation_display_id.present?
  end

  # Redis SET NX returns "OK" only the first time; nil on webhook retries with the same message id.
  def first_delivery?
    Redis::Alfred.set("only_home:webhook:message:#{@payload[:id]}", 1, nx: true, ex: IDEMPOTENCY_TTL).present?
  end

  def content
    @payload[:content]
  end

  def conversation_display_id
    @payload.dig(:conversation, :id)
  end

  def account_id
    @payload.dig(:conversation, :account_id) || @payload.dig(:account, :id)
  end
end
