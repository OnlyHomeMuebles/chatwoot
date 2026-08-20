# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::Tools::GetConversationTool do
  subject(:tool) { described_class.new }

  let(:chatwoot) { instance_double(OnlyHome::ChatwootClient) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { conversation_id: 7, chatwoot_client: chatwoot } }))
  end

  it 'devuelve un transcript etiquetando cliente/agente y omite mensajes sin texto' do
    allow(chatwoot).to receive(:conversation_messages).with(7).and_return(
      [
        { 'content' => 'Hola, tengo un problema con mi pedido', 'message_type' => 0 },
        { 'content' => 'Claro, cuéntame más', 'message_type' => 1 },
        { 'content' => '', 'message_type' => 2 }
      ]
    )

    expect(tool.perform(tool_context)).to eq("Cliente: Hola, tengo un problema con mi pedido\nAgente: Claro, cuéntame más")
  end

  it 'maneja una conversación sin mensajes de texto' do
    allow(chatwoot).to receive(:conversation_messages).and_return([])

    expect(tool.perform(tool_context)).to match(/no tiene mensajes/i)
  end

  it 'devuelve un mensaje de error legible si la API falla' do
    allow(chatwoot).to receive(:conversation_messages).and_raise(OnlyHome::ChatwootClient::ApiError, 'boom')

    expect(tool.perform(tool_context)).to match(/No se pudo completar la acción/)
  end
end
