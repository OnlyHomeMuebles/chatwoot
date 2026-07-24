# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::Tools::AddLabelTool do
  subject(:tool) { described_class.new }

  let(:chatwoot) { instance_double(OnlyHome::ChatwootClient) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { conversation_id: 42, chatwoot_client: chatwoot } }))
  end

  it 'agrega la etiqueta a la conversación' do
    expect(chatwoot).to receive(:add_labels).with(42, 'pqrs')

    expect(tool.perform(tool_context, label: 'pqrs')).to eq("Etiqueta 'pqrs' agregada a la conversación.")
  end

  it 'devuelve un mensaje de error legible si la API falla' do
    allow(chatwoot).to receive(:add_labels).and_raise(OnlyHome::ChatwootClient::ApiError, 'boom')

    expect(tool.perform(tool_context, label: 'x')).to match(/No se pudo completar la acción/)
  end
end
