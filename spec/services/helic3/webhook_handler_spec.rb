# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::WebhookHandler do
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
      .to have_enqueued_job(Helic3::ProcessConversationJob)
      .with(account_id: 1, conversation_id: 7, content: '¿Cuánto cuesta el Sofá Modular Santorini?', imagenes: [])
  end

  it 'ignora un mensaje sin texto y sin adjuntos' do
    expect { described_class.new(incoming_payload.merge(content: '')).process }
      .not_to have_enqueued_job(Helic3::ProcessConversationJob)
  end

  it 'no responde si la conversación ya fue escalada a un humano (estado open)' do
    expect { described_class.new(incoming_payload.merge(conversation: { id: 7, account_id: 1, status: 'open' })).process }
      .not_to have_enqueued_job(Helic3::ProcessConversationJob)
  end

  it 'ignora los mensajes salientes (los del propio agente)' do
    expect { described_class.new(incoming_payload.merge(message_type: 'outgoing')).process }
      .not_to have_enqueued_job(Helic3::ProcessConversationJob)
  end

  it 'ignora las notas privadas' do
    expect { described_class.new(incoming_payload.merge(private: true)).process }
      .not_to have_enqueued_job(Helic3::ProcessConversationJob)
  end

  it 'ignora eventos que no sean message_created' do
    expect { described_class.new(incoming_payload.merge(event: 'conversation_updated')).process }
      .not_to have_enqueued_job(Helic3::ProcessConversationJob)
  end

  it 'es idempotente ante reintentos del webhook con el mismo id de mensaje' do
    allow(Redis::Alfred).to receive(:set).and_return('OK', nil)

    expect { described_class.new(incoming_payload).process }.to have_enqueued_job(Helic3::ProcessConversationJob)
    expect { described_class.new(incoming_payload).process }.not_to have_enqueued_job(Helic3::ProcessConversationJob)
  end

  # AGT-08 + EVI-02: un mensaje solo con foto (sin texto) hace las DOS cosas, no
  # una en lugar de la otra -- son necesidades distintas. El agente responde
  # igual (con lo que el OCR haya leido, ver ProcessConversationJob), y la
  # evidencia se vincula al expediente por su cuenta como red de seguridad
  # independiente (si el job del agente fallara, el documento igual queda).
  describe 'mensajes con adjuntos' do
    let(:solo_imagen_payload) do
      incoming_payload.merge(
        content: '',
        attachments: [
          { file_type: 'image', data_url: 'https://cdn.chatwoot.test/foto-dano.jpg' },
          { file_type: 'audio', data_url: 'https://cdn.chatwoot.test/nota-de-voz.ogg' }
        ]
      )
    end

    it 'un mensaje solo con foto (sin texto) SI hace que el agente responda, con las imagenes para el OCR' do
      expect { described_class.new(solo_imagen_payload).process }
        .to have_enqueued_job(Helic3::ProcessConversationJob)
        .with(account_id: 1, conversation_id: 7, content: '', imagenes: ['https://cdn.chatwoot.test/foto-dano.jpg'])
    end

    it 'un mensaje solo con foto TAMBIEN encola la vinculacion de evidencias' do
      expect { described_class.new(solo_imagen_payload).process }
        .to have_enqueued_job(Helic3::VincularEvidenciasJob).with(account_id: 1, conversation_id: 7)
    end

    it 'un mensaje con texto Y adjuntos encola las dos cosas' do
      con_adjunto = incoming_payload.merge(attachments: [{ file_type: 'image', data_url: 'https://x.test/foto.png' }])

      expect { described_class.new(con_adjunto).process }
        .to have_enqueued_job(Helic3::ProcessConversationJob).and have_enqueued_job(Helic3::VincularEvidenciasJob)
    end

    it 'un mensaje sin texto y sin adjuntos se ignora por completo' do
      vacio = incoming_payload.merge(content: '')

      expect { described_class.new(vacio).process }.not_to have_enqueued_job(Helic3::ProcessConversationJob)
      expect { described_class.new(vacio).process }.not_to have_enqueued_job(Helic3::VincularEvidenciasJob)
    end
  end
end
