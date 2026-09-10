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
  end
end
