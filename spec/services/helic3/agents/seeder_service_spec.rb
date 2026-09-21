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

  # B1 (revision de Jhan): la asignacion de bandejas debe encontrar el bot tanto por
  # el webhook nuevo (/webhooks/helic3) como por la ruta heredada (/webhooks/only_home),
  # que es la que sigue viva en produccion. Si solo mirara 'helic3', en prod no
  # asignaria nada y el bot quedaria mudo al prender la bandera.
  describe 'asignar_bandejas! (H3A-04 crit paridad)' do
    def bandejas_de(account)
      Helic3::AgenteBandeja.where(agente_id: Helic3::Agente.where(account: account).select(:id))
    end

    def conectar_bot(account, inbox, outgoing_url)
      bot = create(:agent_bot, account: account, outgoing_url: outgoing_url)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    end

    it 'vincula los 5 agentes al inbox del bot cuando el webhook es /webhooks/helic3' do
      inbox = create(:inbox, account: account)
      conectar_bot(account, inbox, 'https://app.example.com/webhooks/helic3')

      described_class.new(account).sembrar!

      expect(bandejas_de(account).count).to eq(5)
      expect(bandejas_de(account).where(inbox_id: inbox.id).count).to eq(5)
    end

    it 'tambien vincula cuando el webhook es la ruta heredada /webhooks/only_home' do
      inbox = create(:inbox, account: account)
      conectar_bot(account, inbox, 'https://app.example.com/webhooks/only_home')

      described_class.new(account).sembrar!

      expect(bandejas_de(account).count).to eq(5)
    end

    it 'no asigna ninguna bandeja si no hay un bot de helic3 conectado' do
      inbox = create(:inbox, account: account)
      conectar_bot(account, inbox, 'https://app.example.com/webhooks/otro_servicio')

      resumen = described_class.new(account).sembrar!

      expect(bandejas_de(account).count).to eq(0)
      expect(resumen[:bandejas]).to eq(0)
    end

    it 'es idempotente: no duplica bandejas al sembrar dos veces' do
      inbox = create(:inbox, account: account)
      conectar_bot(account, inbox, 'https://app.example.com/webhooks/helic3')

      described_class.new(account).sembrar!
      described_class.new(account).sembrar!

      expect(bandejas_de(account).count).to eq(5)
    end
  end
end
