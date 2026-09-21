# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::RunnerService do
  subject(:service) { described_class.new(model: 'gpt-4.1-mini') }

  let(:mock_runner) { instance_double(Agents::AgentRunner) }

  def mock_result(output:, agent_name:)
    instance_double(Agents::RunResult, output: output, context: { current_agent: agent_name })
  end

  before do
    allow(Agents::Runner).to receive(:with_agents).and_return(mock_runner)
    allow(mock_runner).to receive(:run).and_return(mock_result(output: 'ok', agent_name: 'agente_triage'))
  end

  it 'registra agente_triage como primer agente (punto de entrada)' do
    expect(Agents::Runner).to receive(:with_agents) do |first, *_rest|
      expect(first.name).to eq('agente_triage')
      mock_runner
    end
    service.run('prueba')
  end

  it 'registra los cinco agentes en el runner' do
    expect(Agents::Runner).to receive(:with_agents) do |*agents|
      expect(agents.map(&:name)).to include('agente_triage', 'agente_faq', 'agente_pqrs',
                                            'agente_logistica', 'agente_cotizaciones')
      mock_runner
    end
    service.run('prueba')
  end

  describe 'sin bucles de handoff' do
    it 'el triage no tiene handoff hacia sí mismo' do
      expect(Agents::Runner).to receive(:with_agents) do |*agents|
        triage = agents.find { |a| a.name == 'agente_triage' }
        expect(triage.handoff_agents.map(&:name)).not_to include('agente_triage')
        mock_runner
      end
      service.run('prueba')
    end

    it 'cada especialista solo tiene handoff al triage' do
      expect(Agents::Runner).to receive(:with_agents) do |*agents|
        agents.reject { |a| a.name == 'agente_triage' }.each do |specialist|
          nombres = specialist.handoff_agents.map(&:name)
          expect(nombres).to eq(['agente_triage']), "#{specialist.name} tiene handoffs inesperados: #{nombres}"
        end
        mock_runner
      end
      service.run('prueba')
    end
  end

  describe 'enrutamiento por dominio' do
    it 'entrega el resultado del especialista de conocimiento ante una consulta FAQ' do
      allow(mock_runner).to receive(:run)
        .and_return(mock_result(output: 'Las puertas son de MDF enchapado.', agent_name: 'agente_faq'))

      result = service.run('¿De qué material son las puertas Milano?')

      expect(result.output).to be_present
      expect(result.context[:current_agent]).to eq('agente_faq')
    end

    it 'entrega el resultado del especialista de PQRS ante una queja' do
      allow(mock_runner).to receive(:run)
        .and_return(mock_result(output: 'Ticket registrado TKT-001.', agent_name: 'agente_pqrs'))

      result = service.run('Quiero poner una queja por mi pedido defectuoso')

      expect(result.output).to be_present
      expect(result.context[:current_agent]).to eq('agente_pqrs')
    end

    it 'entrega el resultado del especialista de logística ante un seguimiento' do
      allow(mock_runner).to receive(:run)
        .and_return(mock_result(output: 'Tu pedido llega el lunes.', agent_name: 'agente_logistica'))

      result = service.run('¿Cuándo llega mi pedido número 12345?')

      expect(result.output).to be_present
      expect(result.context[:current_agent]).to eq('agente_logistica')
    end

    it 'entrega el resultado del especialista de cotizaciones ante una solicitud de precio' do
      allow(mock_runner).to receive(:run)
        .and_return(mock_result(output: 'Cotización: $4.500.000 COP.', agent_name: 'agente_cotizaciones'))

      result = service.run('¿Cuánto cuesta una cocina integral para Bogotá?')

      expect(result.output).to be_present
      expect(result.context[:current_agent]).to eq('agente_cotizaciones')
    end
  end

  # H3A-08 (runner desde la BD) + H3A-12 (bandera por cuenta). Lo de arriba cubre el
  # camino de clases; aqui el camino de base de datos.
  describe 'desde la BD (H3A-08 y H3A-12)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }

    before do
      Helic3::Agents::SeederService.new(account).sembrar!
      Helic3::Agente.where(account: account).find_each do |agente|
        Helic3::AgenteBandeja.create!(agente: agente, inbox: inbox)
      end
    end

    def prender_flag
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'agentes_desde_bd',
                                          valor: 'true', unidad: 'booleano')
    end

    it 'con la bandera apagada usa las clases (modo :clases): comportamiento de hoy' do
      expect(described_class.new(account: account, inbox: inbox).modo).to eq(:clases)
    end

    it 'con la bandera encendida lee la BD y arma la orquesta con el triage primero' do
      prender_flag
      servicio = described_class.new(account: account, inbox: inbox)

      expect(servicio.modo).to eq(:bd)
      expect(servicio.hay_agentes?).to be(true)

      agentes = servicio.send(:build_agents)
      expect(agentes.first.name).to eq('agente_triage')
      expect(agentes.map(&:name)).to contain_exactly(
        'agente_triage', 'agente_faq', 'agente_pqrs', 'agente_logistica', 'agente_cotizaciones'
      )
    end

    it 'en modo :bd sin agentes para la bandeja, hay_agentes? es false (se deja al humano)' do
      prender_flag
      otra_bandeja = create(:inbox, account: account)

      expect(described_class.new(account: account, inbox: otra_bandeja).hay_agentes?).to be(false)
    end
  end
end
