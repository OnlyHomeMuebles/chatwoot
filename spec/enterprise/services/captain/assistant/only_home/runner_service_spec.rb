# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Assistant::OnlyHome::RunnerService do
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
end
