# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::Tools::RadicarPqrTool do
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

  let(:garantia) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
  end

  def radicar(**argumentos)
    tool.perform(tool_context,
                 tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                 resumen: 'Sofá con chapilla levantada',
                 descripcion: 'El cliente reporta la chapilla levantada en el brazo derecho',
                 **argumentos)
  end

  # la porcion del catalogo que la radicacion necesita
  before do
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
    Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo',
                                   plazo_dias_habiles: 15)
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto',
                                        codigo: 'garantia_producto', categoria: garantia)
    allow(chatwoot).to receive(:create_message)
  end

  it 'crea un expediente real: categoria Garantia derivada, vencimiento calculado y origen agente' do
    radicar

    ticket = Helic3::Ticket.last
    expect(ticket.categoria).to eq(garantia)
    expect(ticket.plazo_respuesta_vence_at).to be_present
    expect(ticket.pqrs_metadata).to include('origen' => 'agente')
    # la tool traduce el display_id de Chatwoot al id de base de datos
    expect(ticket.conversation_id).to eq(conversation.id)
  end

  it 'en modo propone (el default sin parametro), la salida NO contiene el numero de radicado' do
    salida = radicar

    expect(salida).to include('registrado')
    expect(salida).not_to include(Helic3::Ticket.last.numero_radicado)
  end

  it 'en modo ejecuta, la salida contiene el numero de radicado' do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'autonomia_radicar_pqr',
                                        valor: 'ejecuta', unidad: 'texto')
    salida = radicar

    expect(salida).to include(Helic3::Ticket.last.numero_radicado)
  end

  it 'con un valor desconocido del parametro se comporta como propone (conservador)' do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'autonomia_radicar_pqr',
                                        valor: 'a_lo_loco', unidad: 'texto')
    salida = radicar

    expect(salida).not_to include(Helic3::Ticket.last.numero_radicado)
  end

  it 'un motivo_codigo inexistente devuelve la lista vigente del catalogo y no levanta excepcion' do
    salida = tool.perform(tool_context, tipo_codigo: 'reclamo', motivo_codigo: 'motivo_inventado',
                                        resumen: 'x', descripcion: 'y')

    expect(salida).to include('garantia_producto')
    expect(Helic3::Ticket.count).to eq(0)

    # la lista se LEE del catalogo: un motivo nuevo aparece sin tocar la tool
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Otro', codigo: 'motivo_nuevo',
                                        categoria: garantia)
    salida = tool.perform(tool_context, tipo_codigo: 'reclamo', motivo_codigo: 'motivo_inventado',
                                        resumen: 'x', descripcion: 'y')
    expect(salida).to include('motivo_nuevo')
  end

  it 'deja la nota privada con la clasificacion elegida y el numero del expediente' do
    expect(chatwoot).to receive(:create_message)
      .with(conversation.display_id,
            content: a_string_matching(/Garantía de producto.*#\d+|#\d+.*Garantía de producto/m),
            private_note: true)

    radicar
  end

  it 'un fallo de la Application API devuelve mensaje legible y no tumba el run ni la radicacion' do
    allow(chatwoot).to receive(:create_message).and_raise(Helic3::ChatwootClient::ApiError, 'boom')

    salida = nil
    expect { salida = radicar }.not_to raise_error
    expect(Helic3::Ticket.count).to eq(1)
    expect(salida).to include('registrado')
  end

  it 'una consulta de categoria Informacion se registra sin numero y lo dice' do
    informacion = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Información',
                                                      codigo: 'informacion', genera_radicado: false)
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Información general',
                                        codigo: 'informacion_general', categoria: informacion)

    salida = tool.perform(tool_context, tipo_codigo: 'reclamo', motivo_codigo: 'informacion_general',
                                        resumen: 'Horarios', descripcion: 'Pregunta por horarios')

    expect(salida).to include('no genera numero de radicado')
    expect(Helic3::Ticket.last.numero_radicado).to be_nil
  end

  it 'si el run no trae cuenta, responde legible sin reventar' do
    ctx = Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: {} }))

    salida = tool.perform(ctx, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                               resumen: 'x', descripcion: 'y')
    expect(salida).to include('cuenta')
  end
end
