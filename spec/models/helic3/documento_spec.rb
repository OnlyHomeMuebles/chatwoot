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

    describe 'el archivo propio (procedencia B, EVI-03 carga manual)' do
      it 'rechaza un archivo mas pesado que el limite configurado' do
        documento = documento_con
        documento.archivo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png',
                                 content_type: 'image/png')
        allow(documento.archivo).to receive(:byte_size).and_return(41.megabytes)

        expect(documento).not_to be_valid
        expect(documento.errors[:archivo]).to include('size is too big')
      end

      it 'rechaza un tipo de archivo no soportado (expediente con valor probatorio ante la SIC)' do
        # ActiveStorage corrige el content_type declarado segun el contenido
        # real del archivo (marcel); por eso el cuerpo tiene que ser
        # genuinamente un ejecutable, no bytes de imagen con un tipo falso.
        documento = documento_con
        documento.archivo.attach(io: StringIO.new("#!/bin/sh\necho hi\n"), filename: 'script.sh',
                                 content_type: 'application/x-sh')

        expect(documento).not_to be_valid
        expect(documento.errors[:archivo]).to include('content type not supported')
      end

      it 'acepta un tipo de la lista de Attachment::ACCEPTABLE_FILE_TYPES (p. ej. PDF)' do
        documento = documento_con
        documento.archivo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'factura.pdf',
                                 content_type: 'application/pdf')

        expect(documento).to be_valid
      end
    end
  end

  describe '#url y #tipo_archivo' do
    it 'resuelven contra el adjunto de la conversacion cuando esa es la procedencia' do
      documento = documento_con(attachment: adjunto)

      expect(documento.url).to be_present
      expect(documento.tipo_archivo).to eq('image/png')
    end

    it 'no revientan cuando el attachment referenciado no trae un archivo real (p. ej. una ubicacion)' do
      sin_blob = mensaje.attachments.create!(account_id: account.id, file_type: :location)
      documento = documento_con(attachment: sin_blob)

      expect(documento.url).to be_nil
      expect(documento.tipo_archivo).to be_nil
    end

    it 'resuelven contra el archivo propio cuando esa es la procedencia' do
      documento = documento_con
      documento.archivo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      documento.save!

      expect(documento.url).to be_present
      expect(documento.tipo_archivo).to eq('image/png')
    end
  end

  # B2 (revision de Jhan): Conversations::MessagesController#destroy borra los
  # attachments del mensaje (message.attachments.destroy_all). Sin on_delete:
  # :nullify en la FK, eso revienta con un 500 si la foto ya esta vinculada a
  # un expediente.
  describe 'cuando se borra el adjunto o el mensaje de origen desde el chat (B2)' do
    it 'borrar el adjunto no revienta: la FK nullifica y el documento sigue existiendo' do
      documento = documento_con(attachment: adjunto)
      documento.save!

      expect { adjunto.destroy! }.not_to raise_error
      expect(documento.reload.attachment_id).to be_nil
    end

    it 'borrar el mensaje (y sus adjuntos en cascada) no revienta' do
      documento = documento_con(attachment: adjunto, message: mensaje)
      documento.save!

      expect { mensaje.attachments.destroy_all }.not_to raise_error
      expect(documento.reload.attachment_id).to be_nil
    end

    it 'conserva titulo, remitente_nombre y ocurrido_at como instantanea' do
      documento = documento_con(attachment: adjunto, titulo: 'factura.png', remitente_nombre: 'Juan Pérez')
      documento.save!
      ocurrido_at = documento.ocurrido_at

      adjunto.destroy!
      documento.reload

      expect(documento).to have_attributes(titulo: 'factura.png', remitente_nombre: 'Juan Pérez')
      expect(documento.ocurrido_at).to be_within(1.second).of(ocurrido_at)
    end

    it 'queda marcado como archivo_eliminado? tras el borrado' do
      documento = documento_con(attachment: adjunto)
      documento.save!

      adjunto.destroy!

      expect(documento.reload.archivo_eliminado?).to be(true)
    end

    it 'un documento nuevo (sin guardar) no se reporta como archivo_eliminado?' do
      expect(documento_con.archivo_eliminado?).to be(false)
    end
  end
end
