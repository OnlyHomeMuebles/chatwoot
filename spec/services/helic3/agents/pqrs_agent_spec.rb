# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::PqrsAgent do
  subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

  it 'se construye como el especialista de PQRS y garantías' do
    expect(agent.name).to eq('agente_pqrs')
    expect(agent.model).to eq('gpt-4.1-mini')
  end

  describe 'instrucciones base' do
    it 'delimitan su responsabilidad a la gestión postventa' do
      expect(described_class::INSTRUCTIONS).to match(/postventa/i)
      expect(described_class::INSTRUCTIONS).to match(/garantía/i)
    end

    it 'prioriza dar siempre una solución concreta al cliente' do
      expect(described_class::INSTRUCTIONS).to match(/siempre una solución/i)
    end

    it 'no tiene ningun plazo quemado en el codigo fuente (criterio grep de AGT-02)' do
      # el criterio aplica al ARCHIVO del agente; PoliticasEstaticas (que las
      # instrucciones interpolan) esta en revision aparte y no se toca aqui
      fuente = Rails.root.join('app/services/helic3/agents/pqrs_agent.rb').read
      expect(fuente).not_to match(/[0-9]+ *(a [0-9]+ )?(días|dias|años|anos|meses)/)
    end

    it 'indica usar la herramienta de radicacion y entregar solo el numero que ella devuelva' do
      expect(described_class::INSTRUCTIONS).to match(/radicar_pqr/)
      expect(described_class::INSTRUCTIONS).to match(/solo entregas el que la herramienta/i)
    end
  end

  describe 'herramientas registradas (AGT-02)' do
    it 'incluye la herramienta de radicacion junto a las existentes' do
      expect(agent.tools.map(&:class)).to include(
        Helic3::Agents::Tools::RadicarPqrTool,
        Helic3::Agents::Tools::HumanHandoffTool,
        Helic3::KnowledgeBaseSearchTool
      )
    end
  end

  describe 'seccion operativa leida del catalogo (AGT-02)' do
    let(:account) { create(:account) }

    before do
      { 'visita_tecnica' => 8, 'recoleccion' => 15, 'cambio_producto' => 20 }
        .each_with_index do |(codigo, plazo), indice|
        Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: codigo.humanize,
                                                  codigo: codigo, plazo_dias_habiles: plazo,
                                                  posicion: indice)
      end
      { 'amparo_garantia' => %w[12 meses], 'plazo_respuesta_pqr' => %w[15 dias_habiles],
        'plazo_retracto' => %w[5 dias_habiles] }.each do |clave, (valor, unidad)|
        Helic3::Catalogo::Parametro.create!(account: account, clave: clave, valor: valor, unidad: unidad)
      end
      Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo',
                                     plazo_dias_habiles: 15)
      categoria = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía',
                                                      codigo: 'garantia')
      Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto',
                                          codigo: 'garantia_producto', categoria: categoria)
    end

    def prompt
      agent.get_system_prompt(Agents::RunContext.new({ account_id: account.id }))
    end

    it 'inyecta los plazos reales del catalogo: 8 de visita, 15 de recoleccion, 12 meses de amparo' do
      expect(prompt).to include('Visita técnica: 8 días hábiles')
      expect(prompt).to include('Recolección: 15 días hábiles')
      expect(prompt).to include('Amparo de la garantía: 12 meses')
    end

    it 'cambiar el plazo en el catalogo cambia las instrucciones, sin tocar codigo' do
      Helic3::Catalogo::ProcesoGarantia.find_by(account: account, codigo: 'visita_tecnica')
                                       .update!(plazo_dias_habiles: 9)

      expect(prompt).to include('Visita técnica: 9 días hábiles')
    end

    it 'inyecta los codigos vigentes para la herramienta de radicacion' do
      expect(prompt).to include('tipo_codigo: reclamo')
      expect(prompt).to include('garantia_producto')
    end
  end

  describe 'instrucciones dinámicas por contexto' do
    it 'inyecta el cliente y el número de orden cuando están en el contexto' do
      prompt = agent.get_system_prompt(
        Agents::RunContext.new({ state: { customer_name: 'Carlos Díaz', order_number: 'ORD-9988' } })
      )

      expect(prompt).to include('Contexto de la conversación')
      expect(prompt).to include('Carlos Díaz')
      expect(prompt).to include('ORD-9988')
    end

    it 'usa solo las instrucciones base cuando no hay contexto' do
      prompt = agent.get_system_prompt(Agents::RunContext.new({}))

      expect(prompt).to eq(described_class::INSTRUCTIONS)
    end
  end
end
