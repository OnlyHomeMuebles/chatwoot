# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::ConfigCache do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  # las FILAS viven en Rails.cache por proceso; en test es :null_store, asi que se
  # usa un MemoryStore real. La VERSION vive en Redis (Redis::Alfred -> MockRedis en
  # test), que es lo que se comparte entre procesos.
  let(:memoria) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(memoria) }

  def crear_agente(codigo, activo: true)
    Helic3::Agente.create!(account: account, codigo: codigo, nombre: codigo,
                           criterio_ruteo: 'x', prompt: 'p', activo: activo).tap do |ag|
      Helic3::AgenteBandeja.create!(agente: ag, inbox: inbox)
    end
  end

  describe '.agentes_para' do
    it 'consulta la BD una sola vez: la segunda es acierto de cache' do
      crear_agente('agente_faq')
      expect(Helic3::Agente).to receive(:activos_para).once.and_call_original

      2.times { described_class.agentes_para(inbox) }
    end

    it 'deja la metrica HIT/MISS en el log (criterio 3)' do
      crear_agente('agente_faq')
      allow(Rails.logger).to receive(:info)

      described_class.agentes_para(inbox) # MISS
      described_class.agentes_para(inbox) # HIT

      expect(Rails.logger).to have_received(:info).with(/MISS/)
      expect(Rails.logger).to have_received(:info).with(/HIT/)
    end

    it 'cae a la BD si la cache de filas falla, sin romper' do
      crear_agente('agente_faq')
      allow(Rails.logger).to receive(:warn)
      allow(memoria).to receive(:fetch).and_raise(StandardError, 'store caido')

      expect(described_class.agentes_para(inbox).map(&:codigo)).to eq(['agente_faq'])
    end
  end

  # revision Jhan: la version se comparte por Redis; hay que probar el problema
  # entre procesos, no el mecanismo dentro de un solo proceso.
  describe 'invalidacion entre procesos' do
    it 'la version se lee de Redis::Alfred, no de Rails.cache' do
      expect(Redis::Alfred).to receive(:get).with(described_class.clave_version(account.id)).and_call_original

      described_class.version(account.id)
    end

    it 'invalidar sube la version en Redis (contador atomico)' do
      expect { described_class.invalidar(account.id) }
        .to(change { described_class.version(account.id) })
    end

    it 'un cambio hecho por OTRO proceso (bump directo en Redis) produce un MISS' do
      crear_agente('agente_faq')
      described_class.agentes_para(inbox) # MISS: cachea en el Rails.cache local

      # "otro proceso" (Puma) sube la version en el Redis compartido
      Redis::Alfred.incr(described_class.clave_version(account.id))

      expect(Helic3::Agente).to receive(:activos_para).and_call_original
      described_class.agentes_para(inbox) # nueva version -> MISS -> re-consulta
    end

    it 'degrada a NO cachear (fuerza MISS) si Redis falla al leer la version' do
      crear_agente('agente_faq')
      described_class.agentes_para(inbox) # cachea bajo la version actual
      allow(Redis::Alfred).to receive(:get).and_raise(StandardError, 'redis caido')

      expect(Helic3::Agente).to receive(:activos_para).and_call_original
      described_class.agentes_para(inbox) # version irrepetible -> MISS -> consulta BD
    end

    it 'no revienta si el account_id es nil' do
      expect { described_class.invalidar(nil) }.not_to raise_error
    end
  end
end
