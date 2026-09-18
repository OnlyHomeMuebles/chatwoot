# frozen_string_literal: true

# Receives Chatwoot agent-bot / account webhooks and hands them to the Helic3 agent system.
# Wire an Agent Bot (bot_type: webhook) with outgoing_url pointing here, or an account webhook
# on the `message_created` event. Always acks fast (head :ok); real work runs in a job.
class Webhooks::Helic3Controller < ActionController::API
  def process_payload
    Helic3::WebhookHandler.new(params.to_unsafe_hash).process
    head :ok
  end
end
