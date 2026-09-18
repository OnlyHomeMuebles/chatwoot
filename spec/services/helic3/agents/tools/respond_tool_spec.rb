# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::Tools::RespondTool do
  subject(:tool) { described_class.new }

  let(:chatwoot) { instance_double(Helic3::ChatwootClient) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { conversation_id: 42, chatwoot_client: chatwoot } }))
  end

  it 'publica el mensaje como respuesta pública (outgoing)' do
    expect(chatwoot).to receive(:create_message).with(42, content: 'Hola, ¿en qué te ayudo?', message_type: 'outgoing')

    expect(tool.perform(tool_context, message: 'Hola, ¿en qué te ayudo?')).to eq('Respuesta enviada al cliente.')
  end

  it 'devuelve un mensaje de error legible si la API falla' do
    allow(chatwoot).to receive(:create_message).and_raise(Helic3::ChatwootClient::ApiError, 'boom')

    expect(tool.perform(tool_context, message: 'x')).to match(/No se pudo completar la acción/)
  end

  it 'falla claro si no hay conversation_id en el contexto' do
    ctx = Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { chatwoot_client: chatwoot } }))

    expect { tool.perform(ctx, message: 'x') }.to raise_error(ArgumentError, /conversation_id/)
  end
end
