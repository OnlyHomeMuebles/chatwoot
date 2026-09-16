# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Knowledge::DatasetPurge do
  let(:account) { create(:account) }

  before do
    adapter = instance_double(Helic3::Knowledge::VectorStore::Base, delete_document: true)
    allow(Helic3::Knowledge::VectorStore).to receive(:adapter).and_return(adapter)
  end

  def dataset(name)
    Helic3::Knowledge::Document.create!(account: account, name: name, source_type: :dataset, content: 'x')
  end

  it 'borra del RAG el dataset cuyo CSV ya no existe (el corpus alienígena)' do
    alien = dataset('casos_servicio_cliente')
    vigente = dataset('respuestas_aprobadas')

    purgados = described_class.new(account, %w[respuestas_aprobadas feedback_categorizado]).call

    expect(purgados).to contain_exactly('casos_servicio_cliente')
    expect(Helic3::Knowledge::Document.exists?(alien.id)).to be(false)
    expect(Helic3::Knowledge::Document.exists?(vigente.id)).to be(true)
  end

  it 'lo saca del vector store, no solo de la tabla' do
    dataset('casos_servicio_cliente')

    expect(Helic3::Knowledge::VectorStore.adapter).to receive(:delete_document)
      .with(an_instance_of(Helic3::Knowledge::Document))

    described_class.new(account, []).call
  end

  it 'protege el catálogo y las conversaciones aprobadas de AGT-05' do
    catalogo = dataset('catalogo_helic3')
    conversacion = dataset('conversacion_42')

    described_class.new(account, []).call

    expect(Helic3::Knowledge::Document.exists?(catalogo.id)).to be(true)
    expect(Helic3::Knowledge::Document.exists?(conversacion.id)).to be(true)
  end

  it 'es idempotente: sin huérfanos no borra nada' do
    dataset('respuestas_aprobadas')

    expect(described_class.new(account, ['respuestas_aprobadas']).call).to be_empty
  end
end
