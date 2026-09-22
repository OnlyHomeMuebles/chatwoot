# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agente, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def nuevo(**attrs)
    described_class.new(
      { account: account, codigo: 'agente_x', nombre: 'X', criterio_ruteo: 'y', prompt: 'instrucciones' }.merge(attrs)
    )
  end

  describe 'validaciones (H3A-02)' do
    it 'exige nombre' do
      expect(nuevo(nombre: '')).not_to be_valid
    end

    it 'exige criterio_ruteo salvo cuando es de sistema' do
      expect(nuevo(criterio_ruteo: nil)).not_to be_valid
      expect(nuevo(criterio_ruteo: nil, es_sistema: true, codigo: 'agente_triage')).to be_valid
    end

    it 'acota confianza_minima a 50..100' do
      expect(nuevo(confianza_minima: 49)).not_to be_valid
      expect(nuevo(confianza_minima: 101)).not_to be_valid
      expect(nuevo(confianza_minima: 85)).to be_valid
    end

    it 'acota max_respuestas a 1..30' do
      expect(nuevo(max_respuestas: 0)).not_to be_valid
      expect(nuevo(max_respuestas: 31)).not_to be_valid
      expect(nuevo(max_respuestas: 8)).to be_valid
    end

    it 'exige codigo unico por cuenta' do
      described_class.create!(account: account, codigo: 'dup', nombre: 'A', criterio_ruteo: 'x', prompt: 'p')
      expect(nuevo(codigo: 'dup')).not_to be_valid
    end

    # H3A-09 (revision de Jhan): sin prompt no hay identidad y el triage revienta.
    it 'exige prompt' do
      expect(nuevo(prompt: nil)).not_to be_valid
      expect(nuevo(prompt: '')).not_to be_valid
    end

    # solo un agente de sistema (el triage) por cuenta
    it 'no permite dos agentes de sistema en la misma cuenta' do
      described_class.create!(account: account, codigo: 'agente_triage', nombre: 'T',
                              es_sistema: true, prompt: 'p')
      otro = nuevo(codigo: 'agente_triage_2', es_sistema: true, criterio_ruteo: nil)
      expect(otro).not_to be_valid
      expect(otro.errors[:es_sistema]).to be_present
    end
  end

  describe 'filtro de herramientas contra el catalogo (H3A-02)' do
    it 'descarta las claves que no estan en el catalogo' do
      agente = nuevo(herramientas: %w[radicar_pqr inventada buscar_conocimiento])
      agente.valid?
      expect(agente.herramientas).to eq(%w[radicar_pqr buscar_conocimiento])
    end
  end

  describe '.activos_para (H3A-02)' do
    it 'devuelve solo los de esa cuenta, esa bandeja y activos' do
      activo = described_class.create!(account: account, codigo: 'a1', nombre: 'A1', criterio_ruteo: 'x',
                                       prompt: 'p', activo: true)
      pausado = described_class.create!(account: account, codigo: 'a2', nombre: 'A2', criterio_ruteo: 'x',
                                        prompt: 'p', activo: false)
      Helic3::AgenteBandeja.create!(agente: activo, inbox: inbox)
      Helic3::AgenteBandeja.create!(agente: pausado, inbox: inbox)

      expect(described_class.activos_para(inbox)).to contain_exactly(activo)
    end
  end

  describe 'proteccion del agente de sistema' do
    it 'no se puede eliminar un es_sistema' do
      sistema = described_class.create!(account: account, codigo: 'agente_triage', nombre: 'T',
                                        es_sistema: true, prompt: 'p')
      expect(sistema.destroy).to be_falsey
      expect(described_class.exists?(sistema.id)).to be(true)
    end
  end
end
