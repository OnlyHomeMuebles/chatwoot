# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::WebhookHandler do
  let(:incoming_payload) do
    {
      event: 'message_created',
      message_type: 'incoming',
      private: false,
      id: 555,
      content: '¿Cuánto cuesta el Sofá Modular Santorini?',
      conversation: { id: 7, account_id: 1, status: 'pending' },
      account: { id: 1 }
    }
  end

  before { allow(Redis::Alfred).to receive(:set).and_return('OK') }

  it 'encola el procesamiento con el contexto de la conversación para un mensaje entrante' do
    expect { described_class.new(incoming_payload).process }
      .to have_enqueued_job(OnlyHome::ProcessConversationJob)
      .with(account_id: 1, conversation_id: 7, content: '¿Cuánto cuesta el Sofá Modular Santorini?')
  end

  it 'no responde si la conversación ya fue escalada a un humano (estado open)' do
    expect { described_class.new(incoming_payload.merge(conversation: { id: 7, account_id: 1, status: 'open' })).process }
      .not_to have_enqueued_job(OnlyHome::ProcessConversationJob)
  end

  it 'ignora los mensajes salientes (los del propio agente)' do
    expect { described_class.new(incoming_payload.merge(message_type: 'outgoing')).process }
      .not_to have_enqueued_job(OnlyHome::ProcessConversationJob)
  end

  it 'ignora las notas privadas' do
    expect { described_class.new(incoming_payload.merge(private: true)).process }
      .not_to have_enqueued_job(OnlyHome::ProcessConversationJob)
  end

  it 'ignora eventos que no sean message_created' do
    expect { described_class.new(incoming_payload.merge(event: 'conversation_updated')).process }
      .not_to have_enqueued_job(OnlyHome::ProcessConversationJob)
  end

  it 'es idempotente ante reintentos del webhook con el mismo id de mensaje' do
    allow(Redis::Alfred).to receive(:set).and_return('OK', nil)

    expect { described_class.new(incoming_payload).process }.to have_enqueued_job(OnlyHome::ProcessConversationJob)
    expect { described_class.new(incoming_payload).process }.not_to have_enqueued_job(OnlyHome::ProcessConversationJob)
  end
end
