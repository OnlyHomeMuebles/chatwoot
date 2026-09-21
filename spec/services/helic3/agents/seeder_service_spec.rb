# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::SeederService do
  let(:account) { create(:account) }

  # H3A-04 criterio 1 y 3
  it 'siembra 5 agentes, es idempotente y deja el triage como es_sistema' do
    described_class.new(account).sembrar!
    described_class.new(account).sembrar!

    expect(Helic3::Agente.where(account: account).count).to eq(5)
    triage = Helic3::Agente.find_by(account: account, codigo: 'agente_triage')
    expect(triage.es_sistema).to be(true)
  end

  # Decision B: el prompt guardado es solo el cuerpo de dominio (sin reglas duras ni tono)
  it 'guarda el cuerpo sin CoreRules ni HumanTone' do
    described_class.new(account).sembrar!
    faq = Helic3::Agente.find_by(account: account, codigo: 'agente_faq')

    expect(faq.prompt).not_to include(Helic3::Agents::CoreRules::GUIDE)
    expect(faq.prompt).not_to include(Helic3::Agents::HumanTone::GUIDE)
  end

  # H3A-04 criterio 4 (paridad): el prompt reensamblado equivale al INSTRUCTIONS original
  it 'reensamblado con PromptBuilder queda igual al INSTRUCTIONS de la clase' do
    described_class.new(account).sembrar!
    normalizar = ->(texto) { texto.to_s.gsub(/\s+/, ' ').strip }

    {
      'agente_faq' => Helic3::Agents::FaqAgent,
      'agente_logistica' => Helic3::Agents::LogisticaAgent,
      'agente_cotizaciones' => Helic3::Agents::CotizacionesAgent
    }.each do |codigo, clase|
      agente = Helic3::Agente.find_by(account: account, codigo: codigo)
      armado = Helic3::Agents::PromptBuilder.new(agente).construir
      expect(normalizar.call(armado)).to eq(normalizar.call(clase::INSTRUCTIONS))
    end
  end
end
