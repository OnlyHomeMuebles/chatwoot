# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::AgenteBandeja, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agente) do
    Helic3::Agente.create!(account: account, codigo: 'a', nombre: 'A', criterio_ruteo: 'x', prompt: 'p')
  end

  it 'no vincula dos veces el mismo inbox a un agente' do
    described_class.create!(agente: agente, inbox: inbox)
    expect(described_class.new(agente: agente, inbox: inbox)).not_to be_valid
  end

  # H3A-06: cambiar la bandeja de un agente invalida la cache de config de la cuenta.
  describe 'invalidacion de cache (H3A-06)' do
    it 'registra el after_commit de invalidacion' do
      expect(described_class._commit_callbacks.map(&:filter)).to include(:invalidar_config_cache)
    end

    it 'invalida la cache de la cuenta del agente' do
      bandeja = described_class.new(agente: agente, inbox: inbox)
      expect(Helic3::Agents::ConfigCache).to receive(:invalidar).with(account.id)
      bandeja.send(:invalidar_config_cache)
    end
  end
end
