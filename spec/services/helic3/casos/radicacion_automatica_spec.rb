# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::RadicacionAutomatica do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  # porcion minima del catalogo que la radicacion necesita
  let(:garantia) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
  end
  let!(:reclamo) do
    Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo',
                                   plazo_dias_habiles: 15)
  end
  let!(:motivo_garantia) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto',
                                        codigo: 'garantia_producto', categoria: garantia)
  end

  let(:extractor) { instance_double(Helic3::Agents::PqrExtractor) }

  def resultado(**attrs)
    Helic3::Agents::PqrExtractor::Resultado.new(**attrs)
  end

  def gate
    described_class.new(account: account, conversation: conversation, extractor: extractor)
  end

  before do
    # la etapa "nueva" es requisito de Casos::Radicar; se crea aqui (no como let!)
    # porque el test no la referencia directamente, solo la necesita presente
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
    create(:message, account: account, conversation: conversation, message_type: :incoming,
                     content: 'Compré un sofá y me llegó con la tela rota, factura 345670')
  end

  describe 'cuando el cliente requiere una PQR con tipo y motivo válidos' do
    before do
      allow(extractor).to receive(:call).and_return(
        resultado(requiere_pqr: true, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                  resumen: 'Sofá con tela rota', descripcion: 'Llegó con la tela rota',
                  numero_orden: '345670')
      )
    end

    it 'radica el expediente por código, ligado a la conversación' do
      expect { gate.call }.to change { account.tickets.count }.by(1)

      ticket = account.tickets.last
      expect(ticket.conversation_id).to eq(conversation.id)
      expect(ticket.tipo).to eq(reclamo)
      expect(ticket.motivo_pqr).to eq(motivo_garantia)
      expect(ticket.categoria).to eq(garantia)
      expect(ticket.pqrs_metadata).to include('origen' => 'agente', 'numero_orden' => '345670')
    end

    it 'devuelve el ticket creado' do
      expect(gate.call).to be_a(Helic3::Ticket)
    end
  end

  describe 'idempotencia: ya existe un expediente para la conversación' do
    before do
      Helic3::Casos::Radicar.new(account: account, titulo: 'Ya radicado',
                                 conversation_id: conversation.id, tipo: reclamo,
                                 motivo_pqr: motivo_garantia).call
    end

    it 'no llama al clasificador y no crea un duplicado' do
      expect(extractor).not_to receive(:call)
      expect { gate.call }.not_to(change { account.tickets.count })
    end

    it 'devuelve :ya_existe' do
      expect(gate.call).to eq(:ya_existe)
    end
  end

  describe 'idempotencia acotada al expediente vigente (respondida_at)' do
    before do
      allow(extractor).to receive(:call).and_return(
        resultado(requiere_pqr: true, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                  resumen: 'Segundo producto', descripcion: 'Otra falla en el mismo hilo')
      )
    end

    it 'con la PQR anterior ya respondida, radica un caso nuevo en el mismo hilo' do
      previa = Helic3::Casos::Radicar.new(account: account, titulo: 'Previa',
                                          conversation_id: conversation.id, tipo: reclamo,
                                          motivo_pqr: motivo_garantia).call
      previa.update_columns(respondida_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect { gate.call }.to change { account.tickets.count }.by(1)
    end
  end

  describe 'cuando el cliente NO requiere una PQR' do
    before { allow(extractor).to receive(:call).and_return(resultado(requiere_pqr: false)) }

    it 'no radica nada' do
      expect(gate.call).to eq(:sin_senal)
      expect(account.tickets).to be_empty
    end
  end

  describe 'cuando el clasificador no pudo (nil) o el código no existe en el catálogo' do
    it 'no radica si el extractor devuelve nil' do
      allow(extractor).to receive(:call).and_return(nil)
      expect(gate.call).to eq(:sin_senal)
      expect(account.tickets).to be_empty
    end

    it 'no radica si el motivo no existe en la cuenta (no inventa códigos)' do
      allow(extractor).to receive(:call).and_return(
        resultado(requiere_pqr: true, tipo_codigo: 'reclamo', motivo_codigo: 'no_existe',
                  resumen: 'x', descripcion: 'y')
      )
      expect(gate.call).to eq(:sin_senal)
      expect(account.tickets).to be_empty
    end
  end

  describe 'el hilo que recibe el clasificador' do
    it 'va etiquetado por quién habló (Cliente/Asistente)' do
      create(:message, account: account, conversation: conversation, message_type: :outgoing,
                       content: 'Lamento lo del sofá, ¿me confirmas la factura?')
      allow(extractor).to receive(:call).and_return(resultado(requiere_pqr: false))

      gate.call

      expect(extractor).to have_received(:call).with(
        a_string_including('Cliente: Compré un sofá').and(including('Asistente: Lamento lo del sofá'))
      )
    end
  end

  describe 'la radicación no se condiciona al consentimiento (base legal de la PQR)' do
    before do
      conversation.update!(custom_attributes: {})
      allow(extractor).to receive(:call).and_return(
        resultado(requiere_pqr: true, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                  resumen: 'Sofá con tela rota', descripcion: 'Llegó con la tela rota')
      )
    end

    it 'radica el expediente aunque la conversación no tenga consentimiento registrado' do
      expect { gate.call }.to change { account.tickets.count }.by(1)
    end
  end
end
