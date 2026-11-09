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
      guardar(cedula: '123', direccion: 'Calle 1', ciudad: 'Armenia', factura_numero: 'OH-1',
              producto_nombre: 'cama')

      datos = ticket.reload.datos
      expect(datos.cedula).to eq('123')
      expect(datos.direccion).to eq('Calle 1')
      expect(datos.ciudad).to eq('Armenia')
      expect(datos.factura_numero).to eq('OH-1')
      expect(datos.producto_nombre).to eq('cama')
      expect(datos.fuentes.values.uniq).to eq(['confirmado'])
    end

    # H3A-17: el producto se deduce de la descripción y se guarda aunque no venga otro dato.
    it 'guarda solo el producto cuando es lo único que trae' do
      guardar(producto_nombre: 'silla de comedor')

      expect(ticket.reload.datos.producto_nombre).to eq('silla de comedor')
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

  # ERP-16 (C2): con el ERP encendido guarda por el camino del formulario (RegistrarDesdeErp):
  # lo que cruza con Siesa queda erp, lo que el cliente corrigio queda confirmado.
  describe 'con el ERP encendido (simulado)' do
    let!(:ticket) { create(:ticket, account: account, conversation_id: conversation.id) }

    around do |ejemplo|
      GlobalConfig.clear_cache
      ejemplo.run
      GlobalConfig.clear_cache
    end

    before { InstallationConfig.create!(name: Helic3::Erp::CLAVE_MODO, value: 'simulado', locked: false) }

    it 'lo que cruza con Siesa queda erp y lo corregido queda confirmado' do
      guardar(cedula: '1.032.456.789', cliente_nombre: 'Ana Ruiz', cliente_telefono: '3001112233',
              direccion: 'Calle nueva 5', ciudad: 'Armenia', factura_numero: 'FV-1001', productos: 'MIL-200')

      ficha = ticket.reload.datos
      expect(ficha.fuentes).to include('cedula' => 'erp', 'cliente_nombre' => 'erp', 'cliente_telefono' => 'erp',
                                       'cliente_email' => 'erp', 'factura_numero' => 'erp', 'factura_fecha' => 'erp',
                                       'direccion' => 'confirmado')
      expect(ficha.direccion).to eq('Calle nueva 5')
      expect(ficha.productos).to eq([{ 'nombre' => 'Puerta Milano', 'referencia' => 'MIL-200', 'fuente' => 'erp' }])
    end

    it 'un producto que no esta en la factura queda confirmado' do
      guardar(cedula: '1032456789', factura_numero: 'FV-1001', producto_nombre: 'Sofa cama')

      ficha = ticket.reload.datos
      expect(ficha.productos).to eq([{ 'nombre' => 'Sofa cama', 'referencia' => '', 'fuente' => 'confirmado' }])
      expect(ficha.fuentes['producto_nombre']).to eq('confirmado')
    end

    it 'con productos elegidos, el producto_nombre deducido no se suma como otro item' do
      guardar(cedula: '1032456789', factura_numero: 'FV-1001', productos: 'MIL-200, CER-050', producto_nombre: 'puerta')

      expect(ticket.reload.datos.productos.pluck('referencia')).to eq(%w[MIL-200 CER-050])
    end

    # Revision #159: un guardado parcial de la compra no reemplaza la lista de productos.
    it 'guardar factura + productos y luego solo factura_numero mantiene los productos' do
      guardar(cedula: '1032456789', factura_numero: 'FV-1001', productos: 'MIL-200, CER-050')
      guardar(cedula: '1032456789', factura_numero: 'FV-1001')

      expect(ticket.reload.datos.productos.pluck('referencia')).to eq(%w[MIL-200 CER-050])
    end

    # Revision #159: con ERP, la compra respeta humano > confirmado > erp igual que sin ERP.
    it 'si el operador corrigio el producto (humano), el agente no lo pisa al guardar la compra' do
      Helic3::Casos::RegistrarDatos.new(ticket: ticket, campos: { producto_nombre: 'Puerta corregida' },
                                        fuente: :humano).call

      guardar(cedula: '1032456789', factura_numero: 'FV-1001', productos: 'MIL-200')

      ficha = ticket.reload.datos
      expect(ficha.producto_nombre).to eq('Puerta corregida')
      expect(ficha.fuentes['producto_nombre']).to eq('humano')
      expect(ficha.productos).to be_blank
    end

    it 'guardar despues solo la direccion no borra los productos ya guardados' do
      guardar(cedula: '1032456789', factura_numero: 'FV-1001', productos: 'MIL-200')
      guardar(direccion: 'Otra 7')

      ficha = ticket.reload.datos
      expect(ficha.productos.pluck('referencia')).to eq(['MIL-200'])
      expect(ficha.direccion).to eq('Otra 7')
    end
  end

  it 'sin expediente vigente no crea ficha y le dice al modelo que radique primero' do
    salida = guardar(direccion: 'Calle 1')

    expect(salida).to match(/radica/i)
    expect(Helic3::TicketDato.count).to eq(0)
  end
end
