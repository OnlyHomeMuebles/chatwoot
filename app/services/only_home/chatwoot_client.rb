# frozen_string_literal: true

require 'httparty'

# Thin HTTP client for Chatwoot's Application API, used by the Only Home agent tools to act on
# a real conversation (reply, private note, labels, custom attributes). Talks to Chatwoot as an
# external system over HTTP, authenticating with an `api_access_token` (a User or AgentBot token).
#
# Config comes from ENV (overridable for tests):
#   ONLY_HOME_CHATWOOT_BASE_URL   (falls back to FRONTEND_URL, then http://localhost:3000)
#   ONLY_HOME_CHATWOOT_ACCOUNT_ID
#   ONLY_HOME_CHATWOOT_API_TOKEN
class OnlyHome::ChatwootClient
  class ApiError < StandardError; end

  DEFAULT_TIMEOUT = 10

  def initialize(base_url: nil, account_id: nil, api_access_token: nil)
    @base_url = (base_url || ENV['ONLY_HOME_CHATWOOT_BASE_URL'] || ENV['FRONTEND_URL'] || 'http://localhost:3000').chomp('/')
    @account_id = account_id || ENV.fetch('ONLY_HOME_CHATWOOT_ACCOUNT_ID')
    @api_access_token = api_access_token || ENV.fetch('ONLY_HOME_CHATWOOT_API_TOKEN')
  end

  # POST /conversations/:id/messages — outgoing reply (public) or private note.
  def create_message(conversation_id, content:, message_type: 'outgoing', private_note: false)
    post("conversations/#{conversation_id}/messages",
         { content: content, message_type: message_type, private: private_note })
  end

  # GET /conversations/:id/labels — current label list for the conversation.
  def labels(conversation_id)
    Array(get("conversations/#{conversation_id}/labels")['payload'])
  end

  # POST /conversations/:id/labels — the endpoint REPLACES the set, so merge to add without removing.
  def add_labels(conversation_id, new_labels)
    merged = (labels(conversation_id) + Array(new_labels)).uniq
    post("conversations/#{conversation_id}/labels", { labels: merged })
  end

  # POST /conversations/:id/custom_attributes — merge/update conversation custom attributes.
  def update_custom_attributes(conversation_id, attributes)
    post("conversations/#{conversation_id}/custom_attributes", { custom_attributes: attributes })
  end

  private

  def post(path, body)
    request(:post, path, body)
  end

  def get(path)
    request(:get, path)
  end

  def request(method, path, body = nil)
    url = "#{@base_url}/api/v1/accounts/#{@account_id}/#{path}"
    response = HTTParty.public_send(method, url, headers: headers, body: body&.to_json, timeout: DEFAULT_TIMEOUT)
    raise ApiError, "Chatwoot API #{method.upcase} #{path} respondió #{response.code}: #{response.body}" unless response.success?

    response.parsed_response
  end

  def headers
    { 'api_access_token' => @api_access_token, 'Content-Type' => 'application/json' }
  end
end
