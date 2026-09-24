# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::VincularEvidencias do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:ticket) { create(:ticket, account: account, conversation: conversation) }

  describe '.call' do
    it 'vincula las evidencias de los tres mensajes con adjuntos de la conversacion' do
      create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'incoming')
      create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'outgoing')
      create(:message, :with_attachment, :bot_message, account: account, conversation: conversation)
      create(:message, account: account, conversation: conversation, message_type: 'incoming') # sin adjunto, se ignora

      documentos = described_class.call(ticket)

      expect(documentos.size).to eq(3)
      expect(ticket.documentos.count).to eq(3)
    end

    it 'es idempotente: correrlo tres veces seguidas deja exactamente los mismos documentos' do
      create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'incoming')
      create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'outgoing')

      3.times { described_class.call(ticket) }

      expect(ticket.documentos.count).to eq(2)
    end

    it 'deriva origen cliente y el nombre del contacto en un mensaje entrante' do
      mensaje = create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'incoming')

      described_class.call(ticket)

      documento = ticket.documentos.first
      expect(documento.origen).to eq('cliente')
      expect(documento.remitente_nombre).to eq(mensaje.sender.name)
      expect(documento.remitente_user_id).to be_nil
    end

    it 'deriva origen operador y el nombre del usuario en un mensaje saliente de un agente humano' do
      mensaje = create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'outgoing')

      described_class.call(ticket)

      documento = ticket.documentos.first
      expect(documento.origen).to eq('operador')
      expect(documento.remitente_nombre).to eq(mensaje.sender.name)
      expect(documento.remitente_user).to eq(mensaje.sender)
    end

    it 'deriva origen agente cuando el mensaje saliente no tiene remitente' do
      create(:message, :with_attachment, :bot_message, account: account, conversation: conversation)

      described_class.call(ticket)

      documento = ticket.documentos.first
      expect(documento.origen).to eq('agente')
      expect(documento.remitente_nombre).to be_nil
    end

    it 'la fecha del documento es la del mensaje, no la de la fila' do
      mensaje = create(:message, :with_attachment, account: account, conversation: conversation,
                                                   created_at: 3.days.ago)

      described_class.call(ticket)

      expect(ticket.documentos.first.ocurrido_at).to be_within(1.second).of(mensaje.created_at)
    end

    it 'el documento apunta al mismo blob del adjunto original, sin duplicar el archivo' do
      mensaje = create(:message, :with_attachment, account: account, conversation: conversation)
      adjunto = mensaje.attachments.first

      described_class.call(ticket)

      documento = ticket.documentos.first
      expect(documento.attachment).to eq(adjunto)
      expect(documento.tipo_archivo).to eq(adjunto.file.content_type)
    end

    it 'registra un evento evidencia_adjuntada por cada documento creado' do
      create(:message, :with_attachment, account: account, conversation: conversation)

      described_class.call(ticket)

      expect(ticket.reload.eventos.pluck(:tipo)).to eq(['evidencia_adjuntada'])
    end

    it 'un expediente sin conversacion no rompe el servicio y devuelve vacio' do
      ticket_sin_conversacion = create(:ticket, account: account)

      expect(described_class.call(ticket_sin_conversacion)).to eq([])
    end
  end
end
