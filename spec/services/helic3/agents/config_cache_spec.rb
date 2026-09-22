# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::ConfigCache do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  # en test el cache_store es :null_store (no persiste); usamos MemoryStore real,
  # que ademas marshaliza como el store de produccion (Redis).
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

    it 'cae a la BD si la cache falla, sin romper' do
      crear_agente('agente_faq')
      allow(Rails.logger).to receive(:warn)
      allow(memoria).to receive(:fetch).and_raise(StandardError, 'redis caido')

      expect(described_class.agentes_para(inbox).map(&:codigo)).to eq(['agente_faq'])
    end
  end

  describe '.invalidar' do
    it 'guardar un agente se refleja tras invalidar (criterio 1)' do
      crear_agente('agente_faq')
      expect(described_class.agentes_para(inbox).size).to eq(1)

      crear_agente('agente_pqrs')
      described_class.invalidar(account.id)

      expect(described_class.agentes_para(inbox).map(&:codigo)).to contain_exactly('agente_faq', 'agente_pqrs')
    end

    it 'pausar un agente lo saca de circulacion tras invalidar (criterio 2)' do
      agente = crear_agente('agente_faq')
      expect(described_class.agentes_para(inbox).size).to eq(1)

      agente.update_column(:activo, false) # rubocop:disable Rails/SkipsModelValidations
      described_class.invalidar(account.id)

      expect(described_class.agentes_para(inbox)).to be_empty
    end

    it 'no revienta si el account_id es nil' do
      expect { described_class.invalidar(nil) }.not_to raise_error
    end
  end
end
