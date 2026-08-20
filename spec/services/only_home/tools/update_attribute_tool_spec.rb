# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::Tools::UpdateAttributeTool do
  subject(:tool) { described_class.new }

  let(:chatwoot) { instance_double(OnlyHome::ChatwootClient) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { conversation_id: 42, chatwoot_client: chatwoot } }))
  end

  it 'guarda el atributo personalizado en la conversación' do
    expect(chatwoot).to receive(:update_custom_attributes).with(42, { 'numero_pedido' => 'ORD-778' })

    expect(tool.perform(tool_context, key: 'numero_pedido', value: 'ORD-778'))
      .to eq("Atributo 'numero_pedido' guardado en la conversación.")
  end

  it 'devuelve un mensaje de error legible si la API falla' do
    allow(chatwoot).to receive(:update_custom_attributes).and_raise(OnlyHome::ChatwootClient::ApiError, 'boom')

    expect(tool.perform(tool_context, key: 'x', value: 'y')).to match(/No se pudo completar la acción/)
  end
end
