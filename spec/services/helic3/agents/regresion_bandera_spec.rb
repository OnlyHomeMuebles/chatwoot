# frozen_string_literal: true

require 'rails_helper'

# H3A-16 (crit 1): regresion de la bandera. Con la bandera APAGADA el runner arma
# los 5 agentes desde las clases; ENCENDIDA los arma desde la BD sembrada. Este
# spec verifica que el comportamiento observable no cambia de forma perceptible:
# mismos agentes, mismas herramientas y misma estructura de handoffs por ambos
# caminos. La paridad del PROMPT de cada agente ya la cubre seeder_service_spec
# (PromptBuilder.construir == INSTRUCTIONS de la clase).
#
# Nota declarada: el triage (H3A-09) arma su directorio de ruteo desde criterio_ruteo
# en el camino :bd, asi que su TEXTO difiere del estatico a proposito; las decisiones
# de ruteo son equivalentes (mismos criterios) y la desambiguacion se conserva.
RSpec.describe 'Helic3 regresion de la bandera agentes_desde_bd (H3A-16)', type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  let(:desde_clases) do
    construir(Helic3::Agents::RunnerService.new(account: account, inbox: inbox, model: 'gpt-4.1-mini')
                                           .send(:build_agents))
  end

  let(:desde_bd) do
    prender_flag
    construir(Helic3::Agents::RunnerService.new(account: account, inbox: inbox, model: 'gpt-4.1-mini')
                                           .send(:build_agents))
  end

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

  def construir(agentes)
    agentes.index_by(&:name)
  end

  def tools_por_clase(agente)
    agente.tools.map(&:class).map(&:to_s).sort
  end

  it 'arma los MISMOS cinco agentes por ambos caminos' do
    esperado = %w[agente_triage agente_faq agente_pqrs agente_logistica agente_cotizaciones]
    expect(desde_clases.keys).to match_array(esperado)
    expect(desde_bd.keys).to match_array(esperado)
  end

  it 'cada agente recibe las MISMAS herramientas por ambos caminos' do
    desde_clases.each_key do |nombre|
      expect(tools_por_clase(desde_bd[nombre])).to eq(tools_por_clase(desde_clases[nombre])),
                                                   "las herramientas de #{nombre} difieren entre bandera off/on"
    end
  end

  it 'conserva la estructura de handoffs (triage -> 4 especialistas; cada uno -> triage)' do
    [desde_clases, desde_bd].each do |agentes|
      triage = agentes['agente_triage']
      expect(triage.handoff_agents.map(&:name)).to match_array(
        %w[agente_faq agente_pqrs agente_logistica agente_cotizaciones]
      )
      agentes.except('agente_triage').each_value do |esp|
        expect(esp.handoff_agents.map(&:name)).to eq(['agente_triage'])
      end
    end
  end
end
