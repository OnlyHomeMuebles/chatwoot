# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Tools::PrivateNoteTool do
  subject(:tool) { described_class.new }

  let(:chatwoot) { instance_double(Helic3::ChatwootClient) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { conversation_id: 42, chatwoot_client: chatwoot } }))
  end

  it 'crea una nota privada (no visible para el cliente)' do
    expect(chatwoot).to receive(:create_message).with(42, content: 'Cliente molesto, priorizar', private_note: true)

    expect(tool.perform(tool_context, note: 'Cliente molesto, priorizar')).to eq('Nota privada agregada.')
  end

  it 'devuelve un mensaje de error legible si la API falla' do
    allow(chatwoot).to receive(:create_message).and_raise(Helic3::ChatwootClient::ApiError, 'boom')

    expect(tool.perform(tool_context, note: 'x')).to match(/No se pudo completar la acción/)
  end
end
