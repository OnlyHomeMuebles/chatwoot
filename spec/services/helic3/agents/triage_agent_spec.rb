# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::TriageAgent do
  describe '.build' do
    subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

    it 'tiene el nombre correcto' do
      expect(agent.name).to eq('agente_triage')
    end

    it 'lleva la herramienta de escalamiento a humano (para pedidos explícitos o casos sensibles)' do
      expect(agent.tools.map { |t| t.class.name }).to include('Helic3::Agents::Tools::HumanHandoffTool')
    end

    it 'sus instrucciones contemplan escalar cuando el cliente pide un humano' do
      expect(described_class::INSTRUCTIONS).to include('herramienta de escalamiento')
    end

    it 'sus instrucciones mencionan los cuatro dominios' do
      expect(described_class::INSTRUCTIONS).to include('agente_faq')
      expect(described_class::INSTRUCTIONS).to include('agente_pqrs')
      expect(described_class::INSTRUCTIONS).to include('agente_logistica')
      expect(described_class::INSTRUCTIONS).to include('agente_cotizaciones')
    end

    it 'sus instrucciones prohíben resolver directamente' do
      expect(described_class::INSTRUCTIONS).to include('No resuelves')
    end
  end

  describe 'registro de handoffs' do
    let(:triage)       { described_class.build(model: 'gpt-4.1-mini') }
    let(:faq)          { Helic3::Agents::FaqAgent.build(model: 'gpt-4.1-mini') }
    let(:pqrs)         { Helic3::Agents::PqrsAgent.build(model: 'gpt-4.1-mini') }
    let(:logistica)    { Helic3::Agents::LogisticaAgent.build(model: 'gpt-4.1-mini') }
    let(:cotizaciones) { Helic3::Agents::CotizacionesAgent.build(model: 'gpt-4.1-mini') }

    before { triage.register_handoffs(faq, pqrs, logistica, cotizaciones) }

    it 'puede transferir a los cuatro especialistas' do
      nombres = triage.handoff_agents.map(&:name)
      expect(nombres).to include('agente_faq', 'agente_pqrs', 'agente_logistica', 'agente_cotizaciones')
    end

    it 'no tiene handoff hacia sí mismo (sin bucles)' do
      expect(triage.handoff_agents.map(&:name)).not_to include('agente_triage')
    end
  end

  # H3A-09: el directorio de ruteo se arma desde los criterio_ruteo de la BD.
  describe 'ruteo dinámico' do
    let(:especialistas) do
      [instance_double(Helic3::Agente, codigo: 'agente_faq',
                                       criterio_ruteo: 'Información general de producto o empresa'),
       instance_double(Helic3::Agente, codigo: 'agente_pqrs',
                                       criterio_ruteo: 'Postventa: algo salió mal con una compra ya hecha')]
    end

    describe '.directorio_dinamico' do
      subject(:directorio) { described_class.directorio_dinamico(especialistas) }

      it 'lista cada especialista con su criterio y su codigo (crit 1)' do
        expect(directorio).to include('agente_faq', 'Información general de producto o empresa')
        expect(directorio).to include('agente_pqrs', 'Postventa: algo salió mal con una compra ya hecha')
      end

      it 'instruye derivar a humano si ningún criterio corresponde (crit 2)' do
        expect(directorio).to include('NINGÚN criterio')
        expect(directorio).to include('herramienta de escalamiento')
      end
    end

    describe '.con_directorio_dinamico' do
      let(:cuerpo) { described_class::INSTRUCTIONS }

      it 'reemplaza el bloque de ruteo estático por el dinámico' do
        resultado = described_class.con_directorio_dinamico(cuerpo, especialistas)

        # el mapa rápido estático desaparece; el criterio de la BD entra
        expect(resultado).not_to include('REGLA DE ORO (decide rápido):')
        expect(resultado).to include('Postventa: algo salió mal con una compra ya hecha')
        # lo que va después del bloque se conserva
        expect(resultado).to include('Desambiguación (casos límite):')
      end

      it 'si el cuerpo no trae las anclas, anexa el directorio al final sin romper (fail-safe)' do
        allow(Rails.logger).to receive(:error)

        resultado = described_class.con_directorio_dinamico('cuerpo editado sin anclas', especialistas)

        expect(resultado).to start_with('cuerpo editado sin anclas')
        expect(resultado).to include('Postventa: algo salió mal con una compra ya hecha')
        expect(Rails.logger).to have_received(:error).with(/no trae las anclas de ruteo/)
      end

      # (revision Jhan) el fail-safe debe cubrir nil y '', no solo un texto sin anclas:
      # la columna prompt es nulable y un admin puede dejarla vacia.
      [nil, ''].each do |cuerpo_vacio|
        it "no revienta con #{cuerpo_vacio.inspect}: anexa el directorio dinámico" do
          allow(Rails.logger).to receive(:error)

          resultado = described_class.con_directorio_dinamico(cuerpo_vacio, especialistas)

          expect(resultado).to include('Postventa: algo salió mal con una compra ya hecha')
          expect(resultado).to include('herramienta de escalamiento')
        end
      end
    end
  end
end
