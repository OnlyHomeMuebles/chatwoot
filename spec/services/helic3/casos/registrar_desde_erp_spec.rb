# frozen_string_literal: true

require 'rails_helper'

# ERP-16 (C6), de punta a punta con el ERP simulado: el cliente manda la foto de su factura (el
# lector de imagenes deja la cedula y el numero como texto), el agente consulta el ERP con ellos,
# radica, guarda los datos y resuelve. El expediente debe quedar igual que uno del formulario
# manual: mismos campos y fuentes, y la garantia con los productos elegidos de la factura.
RSpec.describe Helic3::Casos::RegistrarDesdeErp do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:chatwoot) { instance_double(Helic3::ChatwootClient) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new(
      { account_id: account.id, state: { conversation_id: conversation.display_id, chatwoot_client: chatwoot } }
    ))
  end
  let(:ciudad) { Helic3::Catalogo::CoberturaCiudad.find_by!(account: account, nombre: 'Armenia') }

  around do |ejemplo|
    GlobalConfig.clear_cache
    ejemplo.run
    GlobalConfig.clear_cache
  end

  before do
    Helic3::Catalogo::SeederService.new(account).sembrar!
    InstallationConfig.create!(name: Helic3::Erp::CLAVE_MODO, value: 'simulado', locked: false)
    allow(chatwoot).to receive(:create_message)
  end

  # Lo que hace el agente despues de radicar: con la factura que leyo de la foto (otro formato que
  # el del ERP), consulta, el cliente confirma y corrige la direccion, guarda y resuelve.
  def consultar_guardar_y_resolver(ticket)
    consulta = Helic3::Agents::Tools::ConsultarClienteErpTool.new
                                                             .perform(tool_context, cedula: '1.032.456.789',
                                                                                    factura_numero: 'FV 0001001')
    expect(consulta).to start_with('La factura que mencionó o adjuntó el cliente (FV 0001001) es la FV-1001')

    Helic3::Agents::Tools::RegistrarDatosClienteTool.new.perform(
      tool_context, cedula: '1032456789', cliente_nombre: 'Ana Ruiz', cliente_telefono: '3001112233',
                    cliente_email: 'ana.ruiz@correo.com', direccion: 'Calle corregida 9', ciudad: 'Armenia',
                    factura_numero: 'FV-1001', productos: 'MIL-200'
    )
    Helic3::Agents::Tools::ResolverPqrTool.new.perform(
      tool_context, ticket_display_id: ticket.display_id.to_s, resultado_codigo: 'procede_garantia',
                    ciudad_codigo: ciudad.codigo
    )
    ticket.reload
  end

  def expect_igual_al_formulario(ticket)
    ficha = ticket.datos
    expect(ficha.fuentes).to include('cedula' => 'erp', 'cliente_nombre' => 'erp', 'cliente_telefono' => 'erp',
                                     'cliente_email' => 'erp', 'factura_numero' => 'erp', 'factura_fecha' => 'erp',
                                     'direccion' => 'confirmado')
    expect(ficha.productos).to eq([{ 'nombre' => 'Puerta Milano', 'referencia' => 'MIL-200', 'fuente' => 'erp' }])
    expect(ticket.garantia.items.map { |i| [i.producto_nombre, i.producto_referencia] })
      .to eq([['Puerta Milano', 'MIL-200']])
  end

  it 'radicando con la herramienta del agente' do
    Helic3::Agents::Tools::RadicarPqrTool.new.perform(
      tool_context, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                    resumen: 'Puerta rayada', descripcion: 'La puerta llego rayada', numero_orden: 'FV-1001'
    )

    expect_igual_al_formulario(consultar_guardar_y_resolver(account.tickets.sole))
  end

  it 'radicando con la compuerta automatica (RadicacionAutomatica)' do
    create(:message, account: account, conversation: conversation, message_type: :incoming,
                     content: 'La puerta que compre llego rayada, mi cedula es 1032456789')
    extractor = instance_double(Helic3::Agents::PqrExtractor)
    allow(extractor).to receive(:call).and_return(
      Helic3::Agents::PqrExtractor::Resultado.new(requiere_pqr: true, tipo_codigo: 'reclamo',
                                                  motivo_codigo: 'garantia_producto',
                                                  resumen: 'Puerta rayada', descripcion: 'Llego rayada')
    )
    Helic3::Casos::RadicacionAutomatica.new(account: account, conversation: conversation, extractor: extractor).call

    expect_igual_al_formulario(consultar_guardar_y_resolver(account.tickets.sole))
  end

  # El mismo expediente que deja el formulario manual con la misma cedula (fuente humano en
  # lo corregido): el agente difiere solo en que lo corregido queda confirmado.
  it 'el formulario manual con la misma cedula deja los mismos campos (lo corregido, humano)' do
    ticket = Helic3::Casos::Radicar.new(account: account, titulo: 'Caso', motivo_pqr:
                                          Helic3::Catalogo::MotivoPqr.find_by!(account: account,
                                                                               codigo: 'garantia_producto'),
                                        numero_orden: 'FV-1001').call
    described_class.new(
      ticket: ticket, fuente: :humano,
      datos: { cedula: '1032456789', cliente_nombre: 'Ana Ruiz', direccion: 'Calle corregida 9',
               factura_numero: 'FV-1001', productos: [{ referencia: 'MIL-200' }] }
    ).call

    ficha = ticket.reload.datos
    expect(ficha.fuentes).to include('cedula' => 'erp', 'cliente_nombre' => 'erp', 'factura_numero' => 'erp',
                                     'direccion' => 'humano')
    expect(ficha.productos).to eq([{ 'nombre' => 'Puerta Milano', 'referencia' => 'MIL-200', 'fuente' => 'erp' }])
  end
end
