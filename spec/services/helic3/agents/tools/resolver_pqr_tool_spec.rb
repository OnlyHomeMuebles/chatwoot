# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::Tools::ResolverPqrTool do
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

  let(:ticket) { create(:ticket, account: account) }

  before do
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida',
                                       detiene_reloj: true)
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Resuelta con información',
                                        codigo: 'resuelta_info', cierra_pqr: true)
    allow(chatwoot).to receive(:create_message)
  end

  def resolver(**argumentos)
    tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                               resultado_codigo: 'resuelta_info', **argumentos)
  end

  it 'resuelve el expediente: aplica el resultado y detiene el reloj' do
    resolver

    expect(ticket.reload.resultado.codigo).to eq('resuelta_info')
    expect(ticket).to be_reloj_detenido
  end

  it 'deja nota privada con el resultado' do
    expect(chatwoot).to receive(:create_message)
      .with(conversation.display_id, content: a_string_matching(/Resuelta con información/), private_note: true)

    resolver
  end

  it 'en modo propone (default), la salida NO entrega numero de radicado al cliente' do
    salida = resolver
    expect(salida).to include('pendiente de confirmacion')
  end

  it 'un resultado_codigo inexistente devuelve la lista vigente y no resuelve' do
    salida = tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                        resultado_codigo: 'inventado')

    expect(salida).to include('resuelta_info')
    expect(ticket.reload.resultado).to be_nil
  end

  it 'un ticket inexistente responde legible sin reventar' do
    salida = tool.perform(tool_context, ticket_display_id: '99999', resultado_codigo: 'resuelta_info')
    expect(salida).to include('No existe el expediente')
  end

  describe 'resultado que requiere aprobacion humana' do
    before do
      Helic3::Catalogo::Resultado.create!(account: account, nombre: 'No procede garantía',
                                          codigo: 'garantia_negada', cierra_pqr: true,
                                          aprobacion_humana: true)
    end

    it 'no aplica el resultado y no adelanta una negativa al cliente' do
      salida = tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                          resultado_codigo: 'garantia_negada')

      expect(ticket.reload.resultado_id).to be_nil
      expect(ticket).not_to be_reloj_detenido
      expect(salida).to include('revision')
      expect(salida).not_to include('No procede')
    end
  end

  describe 'resultado que abre garantia' do
    let(:visita) do
      Helic3::Catalogo::ProcesoGarantia.find_by(account: account, codigo: 'visita_tecnica')
    end

    before do
      Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Procede garantía',
                                          codigo: 'procede_garantia', cierra_pqr: true,
                                          abre_garantia: true)
      Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica',
                                                codigo: 'visita_tecnica', posicion: 0)
      Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales',
                                                tecnico_propio: true, origen_ruta: 'visita_tecnica')
      Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Calidad del producto',
                                               codigo: 'calidad_producto')
      Helic3::Catalogo::DetalleTipificado.create!(account: account, nombre: 'Chapilla levantada',
                                                  codigo: 'chapilla_levantada')
    end

    it 'radica la garantia con la ciudad y el producto dados' do
      tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                 resultado_codigo: 'procede_garantia',
                                 ciudad_codigo: 'manizales', producto_nombre: 'Sofá Modular')

      garantia = ticket.reload.garantia
      expect(garantia).to be_present
      expect(garantia.items.first.producto_nombre).to eq('Sofá Modular')
      expect(garantia.items.first.proceso).to eq(visita)
    end

    it 'guarda el producto que dedujo el agente en la ficha con fuente ia (DAT-01)' do
      tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                 resultado_codigo: 'procede_garantia',
                                 ciudad_codigo: 'manizales', producto_nombre: 'Sofá Modular')

      datos = ticket.reload.datos
      expect(datos.producto_nombre).to eq('Sofá Modular')
      expect(datos.fuentes['producto_nombre']).to eq('ia')
    end

    it 'no pisa el producto que el operador ya habia corregido a mano' do
      Helic3::Casos::RegistrarDatos.new(ticket: ticket, campos: { producto_nombre: 'Sofá corregido' },
                                        fuente: :humano).call

      tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                 resultado_codigo: 'procede_garantia',
                                 ciudad_codigo: 'manizales', producto_nombre: 'Sofá Modular')

      expect(ticket.reload.datos.producto_nombre).to eq('Sofá corregido')
    end

    it 'una ciudad invalida NO crea garantia y devuelve la lista de ciudades vigentes' do
      salida = nil
      expect do
        salida = tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                            resultado_codigo: 'procede_garantia',
                                            ciudad_codigo: 'ciudad_inventada', producto_nombre: 'Sofá')
      end.not_to change(Helic3::Garantia, :count)

      expect(ticket.reload.resultado).to be_nil
      expect(salida).to include('manizales')
    end

    it 'clasifica la garantia con el motivo y el detalle dados por el agente' do
      tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                 resultado_codigo: 'procede_garantia', ciudad_codigo: 'manizales',
                                 producto_nombre: 'Sofá Modular', producto_referencia: 'REF-9',
                                 motivo_garantia_codigo: 'calidad_producto',
                                 detalle_tipificado_codigo: 'chapilla_levantada')

      item = ticket.reload.garantia.items.first
      expect(item.motivo_garantia.codigo).to eq('calidad_producto')
      expect(item.detalle_tipificado.codigo).to eq('chapilla_levantada')
      expect(item.producto_referencia).to eq('REF-9')
      # el detalle tambien queda en la ficha con fuente ia (DAT-01)
      expect(ticket.datos.detalle_tipificado.codigo).to eq('chapilla_levantada')
      expect(ticket.datos.fuentes['detalle_tipificado_id']).to eq('ia')
    end

    it 'un detalle_tipificado invalido NO crea garantia y devuelve la lista vigente' do
      salida = nil
      expect do
        salida = tool.perform(tool_context, ticket_display_id: ticket.display_id.to_s,
                                            resultado_codigo: 'procede_garantia', ciudad_codigo: 'manizales',
                                            producto_nombre: 'Sofá', detalle_tipificado_codigo: 'inventado')
      end.not_to change(Helic3::Garantia, :count)

      expect(salida).to include('chapilla_levantada')
    end
  end
end
