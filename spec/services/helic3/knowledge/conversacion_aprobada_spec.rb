# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Knowledge::ConversacionAprobada do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:embedder) { instance_double(Helic3::Knowledge::EmbeddingService) }

  before do
    # embedding stubeado: no pega a la API y devuelve un vector de la dimension real
    allow(Helic3::Knowledge::EmbeddingService).to receive(:new).and_return(embedder)
    allow(embedder).to receive(:embed_batch) { |batch| batch.map { Array.new(1536, 1.0) } }
  end

  # la base de test acumula documentos de otras corridas: se acota SIEMPRE a la
  # cuenta (fresca por test), nunca a los conteos globales de la tabla
  def documentos
    Helic3::Knowledge::Document.where(account: account)
  end

  def aprobar(conv)
    conv.update!(label_list: [described_class::ETIQUETA_APROBACION])
  end

  def mensaje(tipo, contenido)
    create(:message, account: account, conversation: conversation, message_type: tipo, content: contenido)
  end

  describe 'la etiqueta es la unica puerta (criterio 1)' do
    it 'una conversacion sin la etiqueta voz_aprobada nunca se ingesta' do
      mensaje(:incoming, 'Compre un sofa y me llego roto')

      expect(described_class.new(conversation).call).to eq(:no_aprobada)
      expect(documentos.count).to eq(0)
    end
  end

  describe 'idempotencia (criterio 2)' do
    before do
      aprobar(conversation)
      mensaje(:incoming, 'Compre un sofa y me llego con la tela rota')
      mensaje(:outgoing, 'Lamento lo del sofa, con gusto te ayudo con la garantia')
    end

    it 'la primera corrida ingesta y persiste el documento con el nombre convenido' do
      expect(described_class.new(conversation).call).to eq(:ingested)

      document = documentos.sole
      expect(document.name).to eq("conversacion_#{conversation.display_id}")
      expect(document.source_type).to eq('dataset')
      expect(document.chunks.count).to be_positive
    end

    it 'correrla dos veces no crea un segundo documento ni duplica chunks' do
      described_class.new(conversation).call
      chunks_primera = documentos.sole.chunks.count

      expect(described_class.new(conversation).call).to eq(:unchanged)
      expect(documentos.count).to eq(1)
      expect(documentos.sole.chunks.count).to eq(chunks_primera)
    end
  end

  describe 'anonimizacion antes de persistir (criterio 3)' do
    let(:datos_personales) do
      { nombre: 'Maria Fernanda Gomez', cedula: '1032456789', telefono: '3009998888',
        correo: 'juan.perez@gmail.com', direccion: 'Calle 123 # 45-67', factura: '345670' }
    end

    before do
      aprobar(conversation)
      conversation.contact.update!(name: datos_personales[:nombre])
      mensaje(:incoming, "Hola, soy #{datos_personales[:nombre]} y mi sofa llego roto")
      mensaje(:incoming, "Mi cedula es #{datos_personales[:cedula]}, mi celular #{datos_personales[:telefono]}")
      mensaje(:incoming, "Escribeme a #{datos_personales[:correo]}, vivo en la #{datos_personales[:direccion]}")
      mensaje(:incoming, "Adjunto la factura #{datos_personales[:factura]}")
      mensaje(:outgoing, 'Con gusto reviso tu caso de garantia')
    end

    it 'ningun chunk almacenado contiene datos que identifiquen al titular' do
      described_class.new(conversation).call

      corpus = Helic3::Knowledge::Chunk.where(account: account).pluck(:content).join("\n")
      datos_personales.each_value do |dato|
        expect(corpus).not_to include(dato)
      end
      # el nombre tambien por partes
      expect(corpus).not_to include('Fernanda')
    end

    it 'conserva el dialogo por turnos (Cliente / Asesor) para aprender la forma' do
      described_class.new(conversation).call

      contenido = documentos.sole.content
      expect(contenido).to include('Cliente:').and include('Asesor:')
      expect(contenido).to include('garantia')
    end
  end

  describe 'fallo de embedding, no en silencio (criterio 4)' do
    before do
      aprobar(conversation)
      mensaje(:incoming, 'Compre un sofa y me llego roto')
      allow(embedder).to receive(:embed_batch)
        .and_raise(Helic3::Knowledge::EmbeddingService::EmbeddingError, 'la API fallo')
    end

    it 'deja el documento en failed con el error en metadata' do
      expect { described_class.new(conversation).call }
        .to raise_error(Helic3::Knowledge::EmbeddingService::EmbeddingError)

      document = documentos.sole
      expect(document.status).to eq('failed')
      expect(document.metadata['last_error']).to include('la API fallo')
    end
  end

  describe 'derecho de supresión por display_id (habeas data)' do
    before do
      aprobar(conversation)
      mensaje(:incoming, 'Compre un sofa y me llego roto')
    end

    it 'borra el documento y sus chunks del corpus' do
      described_class.new(conversation).call
      expect(documentos.count).to eq(1)

      resultado = described_class.suprimir(account, conversation.display_id)

      expect(resultado).to eq(:suprimida)
      expect(documentos.count).to eq(0)
      expect(Helic3::Knowledge::Chunk.where(account: account)).to be_empty
    end

    it 'es idempotente: si no está en el corpus, devuelve :inexistente' do
      expect(described_class.suprimir(account, conversation.display_id)).to eq(:inexistente)
    end
  end
end
