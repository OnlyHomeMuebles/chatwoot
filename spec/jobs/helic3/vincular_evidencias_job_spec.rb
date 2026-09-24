# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::VincularEvidenciasJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  it 'vincula las evidencias del expediente que ya existe para la conversacion' do
    ticket = create(:ticket, account: account, conversation: conversation)
    create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'incoming')

    described_class.new.perform(account_id: account.id, conversation_id: conversation.display_id)

    expect(ticket.reload.documentos.count).to eq(1)
  end

  it 'no hace nada si todavia no existe un expediente para la conversacion' do
    create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'incoming')

    expect { described_class.new.perform(account_id: account.id, conversation_id: conversation.display_id) }
      .not_to raise_error
  end

  it 'no rompe si la conversacion no existe' do
    expect { described_class.new.perform(account_id: account.id, conversation_id: 999_999) }.not_to raise_error
  end

  it 'atrapa y registra un error inesperado sin propagarlo (best-effort)' do
    create(:ticket, account: account, conversation: conversation)
    allow(Helic3::Casos::VincularEvidencias).to receive(:call).and_raise(StandardError, 'boom')

    expect(Rails.logger).to receive(:error).with(/vincular_evidencias/)
    expect { described_class.new.perform(account_id: account.id, conversation_id: conversation.display_id) }
      .not_to raise_error
  end
end
