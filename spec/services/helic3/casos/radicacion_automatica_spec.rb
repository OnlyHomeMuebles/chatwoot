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
    # la etapa inicial es requisito de Casos::Radicar; se crea aqui (no como let!)
    # porque el test no la referencia directamente, solo la necesita presente
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nuevo', codigo: 'nuevo', inicial: true)
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

  describe 'idempotencia acotada al expediente vigente (respondida_at), via ExpedienteVigente (ERP-06/T2)' do
    before do
      allow(extractor).to receive(:call).and_return(
        resultado(requiere_pqr: true, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                  resumen: 'Segundo producto', descripcion: 'Otra falla en el mismo hilo')
      )
    end

    def radicar_previa(respondida_at:)
      previa = Helic3::Casos::Radicar.new(account: account, titulo: 'Previa',
                                          conversation_id: conversation.id, tipo: reclamo,
                                          motivo_pqr: motivo_garantia).call
      previa.update_columns(respondida_at: respondida_at) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'con la PQR anterior respondida hace 20 minutos (fuera de la ventana), radica un caso nuevo' do
      radicar_previa(respondida_at: 20.minutes.ago)

      expect { gate.call }.to change { account.tickets.count }.by(1)
    end

    it 'con la PQR anterior respondida hace 5 minutos (dentro de la ventana), NO radica' do
      radicar_previa(respondida_at: 5.minutes.ago)

      expect(extractor).not_to receive(:call)
      expect { gate.call }.not_to(change { account.tickets.count })
      expect(gate.call).to eq(:ya_existe)
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

  # ERP-06/T2, ciclo completo: el agente radica con su herramienta, resuelve con la
  # suya, y cuando llega otro mensaje y corre la compuerta automatica (el mismo ciclo
  # que duplicaba expedientes en vivo), debe quedar UN solo expediente -- la regla la
  # comparten ambos caminos via Helic3::Casos::ExpedienteVigente.
  describe 'ciclo completo: la herramienta radica, resolver_pqr la responde, llega otro mensaje y corre la compuerta' do
    let(:chatwoot) { instance_double(Helic3::ChatwootClient) }
    let(:tool_context) do
      Agents::ToolContext.new(run_context: Agents::RunContext.new(
        { account_id: account.id,
          state: { conversation_id: conversation.display_id, chatwoot_client: chatwoot } }
      ))
    end

    before do
      Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Solucionado', codigo: 'solucionado',
                                         detiene_reloj: true)
      Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Resuelta con información',
                                          codigo: 'resuelta_info', cierra_pqr: true)
      allow(chatwoot).to receive(:create_message)
    end

    it 'deja un solo expediente' do
      Helic3::Agents::Tools::RadicarPqrTool.new.perform(
        tool_context, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                      resumen: 'Sofá con tela rota', descripcion: 'Llegó con la tela rota'
      )
      ticket = account.tickets.sole
      Helic3::Agents::Tools::ResolverPqrTool.new.perform(
        tool_context, ticket_display_id: ticket.display_id.to_s, resultado_codigo: 'resuelta_info'
      )
      expect(ticket.reload).to be_reloj_detenido # responder! ya corrio

      # llega otro mensaje del cliente en el mismo hilo y corre la compuerta
      create(:message, account: account, conversation: conversation, message_type: :incoming,
                       content: 'Ah, ya les cuento otra cosa')
      allow(extractor).to receive(:call).and_return(
        resultado(requiere_pqr: true, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                  resumen: 'Otra cosa', descripcion: 'Otra cosa')
      )

      expect { gate.call }.not_to(change { account.tickets.count })
      expect(account.tickets.sole).to eq(ticket)
    end
  end
end
