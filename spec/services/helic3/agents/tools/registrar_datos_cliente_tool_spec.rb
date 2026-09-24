# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::Tools::RegistrarDatosClienteTool do
  subject(:tool) { described_class.new }

  let(:account) { create(:account) }
  let(:chatwoot) { instance_double(Helic3::ChatwootClient) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new(
      { account_id: account.id,
        state: { conversation_id: conversation.display_id, chatwoot_client: chatwoot } }
    ))
  end

  before { allow(chatwoot).to receive(:create_message) }

  def guardar(**argumentos)
    tool.perform(tool_context, **argumentos)
  end

  describe 'con un expediente vigente en la conversacion' do
    let!(:ticket) { create(:ticket, account: account, conversation_id: conversation.id) }

    it 'guarda los datos del cliente en la ficha con fuente confirmado' do
      guardar(cedula: '123', direccion: 'Calle 1', ciudad: 'Armenia', factura_numero: 'OH-1')

      datos = ticket.reload.datos
      expect(datos.cedula).to eq('123')
      expect(datos.direccion).to eq('Calle 1')
      expect(datos.ciudad).to eq('Armenia')
      expect(datos.factura_numero).to eq('OH-1')
      expect(datos.fuentes.values.uniq).to eq(['confirmado'])
    end

    it 'guarda solo los datos que llegan; los vacios no tocan la ficha' do
      guardar(direccion: 'Calle 2')

      expect(ticket.reload.datos.direccion).to eq('Calle 2')
      expect(ticket.datos.cedula).to be_nil
    end

    # H3A-17: el dato confirmado por el cliente NO pisa la correccion de una persona.
    it 'no pisa lo que corrigio una persona (humano > confirmado)' do
      Helic3::Casos::RegistrarDatos.new(ticket: ticket, campos: { direccion: 'la del operador' },
                                        fuente: :humano).call
      guardar(direccion: 'la del cliente')

      expect(ticket.reload.datos.direccion).to eq('la del operador')
    end

    it 'deja una nota privada para el operador' do
      expect(chatwoot).to receive(:create_message)
        .with(conversation.display_id, hash_including(message_type: 'activity'))

      guardar(ciudad: 'Armenia')
    end

    it 'sin ningun dato no escribe la ficha y le pide al modelo pedir uno' do
      salida = guardar

      expect(salida).to match(/no recib/i)
      expect(ticket.reload.datos).to be_nil
    end
  end

  it 'sin expediente vigente no crea ficha y le dice al modelo que radique primero' do
    salida = guardar(direccion: 'Calle 1')

    expect(salida).to match(/radica/i)
    expect(Helic3::TicketDato.count).to eq(0)
  end
end
