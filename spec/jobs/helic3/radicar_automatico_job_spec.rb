# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::RadicarAutomaticoJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:client) { instance_double(Helic3::ChatwootClient) }
  let(:job) { described_class.new }

  let(:garantia) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia') }
  let(:reclamo) do
    Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo', plazo_dias_habiles: 15)
  end
  let(:motivo) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto',
                                        codigo: 'garantia_producto', categoria: garantia)
  end
  let(:ticket) do
    Helic3::Casos::Radicar.new(account: account, titulo: 'Sofá roto', conversation_id: conversation.id,
                               tipo: reclamo, motivo_pqr: motivo).call
  end

  before do
    # la etapa "nueva" es requisito de Casos::Radicar; se crea aqui (no como let!) porque
    # el test no la referencia directamente, solo la necesita presente.
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
    allow(Helic3::ChatwootClient).to receive(:new).and_return(client)
    allow(client).to receive(:create_message)
  end

  def run
    job.perform(account_id: account.id, conversation_id: conversation.display_id)
  end

  describe 'cuando la compuerta radica un expediente' do
    before do
      gate = instance_double(Helic3::Casos::RadicacionAutomatica, call: ticket)
      allow(Helic3::Casos::RadicacionAutomatica).to receive(:new).and_return(gate)
    end

    it 'deja la nota privada de paridad al operador' do
      expect(client).to receive(:create_message)
        .with(conversation.display_id, hash_including(message_type: 'activity'))
      run
    end

    it 'en modo ejecuta le avisa el radicado al cliente' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'autonomia_radicar_pqr',
                                          valor: 'ejecuta', unidad: 'texto')
      expect(client).to receive(:create_message)
        .with(conversation.display_id, hash_including(message_type: 'outgoing'))
      run
    end

    it 'en modo propone NO le manda un mensaje saliente al cliente' do
      expect(client).not_to receive(:create_message)
        .with(conversation.display_id, hash_including(message_type: 'outgoing'))
      run
    end
  end

  describe 'cuando no hay señal para radicar' do
    before do
      gate = instance_double(Helic3::Casos::RadicacionAutomatica, call: :sin_senal)
      allow(Helic3::Casos::RadicacionAutomatica).to receive(:new).and_return(gate)
    end

    it 'no deja nota ni mensaje' do
      expect(client).not_to receive(:create_message)
      run
    end
  end
end
