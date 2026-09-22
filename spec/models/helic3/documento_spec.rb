# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Documento do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:mensaje) { create(:message, :with_attachment, account: account) }
  let(:adjunto) { mensaje.attachments.first }

  def documento_con(**)
    described_class.new(account: account, ticket: ticket, clase: 'evidencia', origen: 'cliente',
                        ocurrido_at: Time.current, **)
  end

  describe 'validaciones' do
    it 'rechaza una clase fuera de la lista cerrada' do
      documento = documento_con(clase: 'lo que sea', attachment: adjunto)

      expect(documento).not_to be_valid
      expect(documento.errors[:clase]).to be_present
    end

    it 'rechaza un origen fuera de la lista cerrada' do
      documento = documento_con(attachment: adjunto, origen: 'marciano')

      expect(documento).not_to be_valid
      expect(documento.errors[:origen]).to be_present
    end

    it 'es invalido sin ninguna procedencia' do
      documento = documento_con

      expect(documento).not_to be_valid
      expect(documento.errors[:base]).to be_present
    end

    it 'es invalido con las dos procedencias a la vez' do
      documento = documento_con(attachment: adjunto)
      documento.archivo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')

      expect(documento).not_to be_valid
      expect(documento.errors[:base]).to be_present
    end

    it 'es valido con solo un adjunto de la conversacion' do
      expect(documento_con(attachment: adjunto)).to be_valid
    end

    it 'es valido con solo un archivo propio' do
      documento = documento_con
      documento.archivo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')

      expect(documento).to be_valid
    end

    it 'rechaza un adjunto de otra cuenta' do
      otra_cuenta = create(:account)
      documento = documento_con(attachment: adjunto, account: otra_cuenta,
                                ticket: create(:ticket, account: otra_cuenta))

      expect(documento).not_to be_valid
      expect(documento.errors[:attachment]).to be_present
    end
  end

  describe '#url y #tipo_archivo' do
    it 'resuelven contra el adjunto de la conversacion cuando esa es la procedencia' do
      documento = documento_con(attachment: adjunto)

      expect(documento.url).to be_present
      expect(documento.tipo_archivo).to eq('image/png')
    end

    it 'resuelven contra el archivo propio cuando esa es la procedencia' do
      documento = documento_con
      documento.archivo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      documento.save!

      expect(documento.url).to be_present
      expect(documento.tipo_archivo).to eq('image/png')
    end
  end
end
