# frozen_string_literal: true

# Entry point for the Only Home Copilot: given a Chatwoot conversation and the human agent's
# request, returns a suggested reply/answer FOR THE AGENT (never posted to the customer).
# Runs the copilot agent (ai-agents) with the run context tied to the conversation.
class Helic3::Copilot::SuggestionService
  def initialize(model: nil)
    @model = model
  end

  # @param conversation_id [Integer] Chatwoot conversation display_id
  # @param query [String] what the agent asks the copilot (e.g. "redáctame una respuesta")
  # @param history [Array<Hash>] optional prior copilot turns for continuity
  # @param chatwoot_client [Helic3::ChatwootClient, nil] injectable (defaults from ENV)
  # @return [String] the copilot's suggestion for the agent
  def suggest(conversation_id:, query:, history: [], chatwoot_client: nil)
    state = { conversation_id: conversation_id }
    state[:chatwoot_client] = chatwoot_client if chatwoot_client

    context = { state: state }
    context[:conversation_history] = history if history.present?

    runner.run(query, context: context).output.to_s
  end

  private

  def runner
    @runner ||= Agents::Runner.with_agents(Helic3::Copilot::Agent.build(model: @model))
  end
end
