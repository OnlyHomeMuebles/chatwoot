# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::Tools::RegistrarConsentimientoTool do
  subject(:tool) { described_class.new }

  let(:account) { create(:account) }
  let(:chatwoot) { instance_double(Helic3::ChatwootClient) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new(
      { account_id: account.id,
        state: { conversation_id: conversation.display_id, chatwoot_client: chatwoot } }
    ))
  end

  before do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'aviso_datos_personales',
                                        valor: 'Aviso oficial de tratamiento de datos', unidad: 'texto')
    allow(chatwoot).to receive(:update_custom_attributes)
    allow(chatwoot).to receive(:create_message)
  end

  it 'sella el consentimiento en el atributo de la conversación' do
    expect(chatwoot).to receive(:update_custom_attributes)
      .with(conversation.display_id, hash_including('helic3_consentimiento_datos_at'))

    tool.perform(tool_context)
  end

  it 'deja una nota privada con el texto exacto del aviso vigente' do
    expect(chatwoot).to receive(:create_message)
      .with(conversation.display_id,
            hash_including(content: a_string_including('Aviso oficial de tratamiento de datos'),
                           message_type: 'activity'))

    tool.perform(tool_context)
  end

  it 'le dice al modelo que no vuelva a mostrar el aviso' do
    expect(tool.perform(tool_context)).to match(/registrado/i)
  end
end
