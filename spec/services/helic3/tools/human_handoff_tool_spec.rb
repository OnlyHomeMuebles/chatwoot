# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Tools::HumanHandoffTool do
  subject(:tool) { described_class.new }

  let(:chatwoot) { instance_double(Helic3::ChatwootClient) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { conversation_id: 42, chatwoot_client: chatwoot } }))
  end

  before do
    allow(chatwoot).to receive(:create_message)
    allow(chatwoot).to receive(:add_labels)
    allow(chatwoot).to receive(:update_status)
    allow(chatwoot).to receive(:assign)
  end

  it 'registra el motivo como nota privada, etiqueta y reabre la conversación para un humano' do
    expect(chatwoot).to receive(:create_message).with(42, content: a_string_including('cliente muy molesto'), private_note: true)
    expect(chatwoot).to receive(:add_labels).with(42, 'escalado-humano')
    expect(chatwoot).to receive(:update_status).with(42, 'open')

    expect(tool.perform(tool_context, reason: 'cliente muy molesto, caso legal'))
      .to eq('Conversación derivada a un agente humano.')
  end

  it 'asigna a un equipo cuando el contexto trae human_team_id' do
    ctx = Agents::ToolContext.new(
      run_context: Agents::RunContext.new({ state: { conversation_id: 42, chatwoot_client: chatwoot, human_team_id: 9 } })
    )
    expect(chatwoot).to receive(:assign).with(42, team_id: 9)

    tool.perform(ctx, reason: 'x')
  end

  it 'no asigna equipo si no hay human_team_id en el contexto' do
    expect(chatwoot).not_to receive(:assign)

    tool.perform(tool_context, reason: 'x')
  end

  it 'devuelve un mensaje de error legible si la API falla' do
    allow(chatwoot).to receive(:create_message).and_raise(Helic3::ChatwootClient::ApiError, 'boom')

    expect(tool.perform(tool_context, reason: 'x')).to match(/No se pudo completar la acción/)
  end
end
