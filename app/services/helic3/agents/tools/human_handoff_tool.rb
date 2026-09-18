# frozen_string_literal: true

# Escalates the conversation to a human agent when an agent can't (or shouldn't) resolve it.
# Equivalent to Captain's human handoff: leaves the reason as a private note, tags the conversation,
# optionally assigns it to a team, and reopens it so a human picks it up.
# API: messages (private note) + labels + assignments + toggle_status.
class Helic3::Agents::Tools::HumanHandoffTool < Helic3::Agents::Tools::BaseTool
  ESCALATION_LABEL = 'escalado-humano'

  description 'Escala la conversación a un agente humano cuando no puedes resolver la solicitud.'
  param :reason, type: 'string', desc: 'Motivo breve de la derivación, para que el humano tenga contexto'

  def perform(tool_context, reason:)
    with_api_error_handling do
      cid = conversation_id(tool_context)
      chatwoot = client(tool_context)

      chatwoot.create_message(cid, content: "Derivación a humano. Motivo: #{reason}", private_note: true)
      chatwoot.add_labels(cid, ESCALATION_LABEL)
      team_id = tool_context.state[:human_team_id]
      chatwoot.assign(cid, team_id: team_id) if team_id
      chatwoot.update_status(cid, 'open')

      # Marca la derivación para que el job garantice un mensaje al cliente aunque el agente no
      # genere texto tras usar la herramienta.
      tool_context.state[:escalated] = true
      'Conversación derivada a un agente humano.'
    end
  end
end
