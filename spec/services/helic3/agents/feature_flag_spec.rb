# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::FeatureFlag do
  let(:account) { create(:account) }

  def poner_flag(valor)
    Helic3::Catalogo::Parametro.create!(
      account: account, clave: described_class::CLAVE_AGENTES_DESDE_BD,
      valor: valor, unidad: 'booleano'
    )
  end

  describe '.agentes_desde_bd?' do
    # H3A-12 / L-09: apagada por defecto. Sin fila (o con la fila sembrada en 'false')
    # el runner usa las clases actuales.
    it 'es false cuando no hay parametro' do
      expect(described_class.agentes_desde_bd?(account)).to be(false)
    end

    it "es false con el valor sembrado por defecto 'false'" do
      poner_flag('false')
      expect(described_class.agentes_desde_bd?(account)).to be(false)
    end

    it 'es false cuando la cuenta es nil' do
      expect(described_class.agentes_desde_bd?(nil)).to be(false)
    end

    it "es true con 'true'" do
      poner_flag('true')
      expect(described_class.agentes_desde_bd?(account)).to be(true)
    end

    # B2 (revision de Jhan): el lector canonico valor_booleano acepta las formas que
    # un panel podria guardar; antes un '== true' seco las dejaba apagadas en silencio.
    %w[1 t T True TRUE on].each do |valor|
      it "es true con '#{valor}' (lector canonico valor_booleano)" do
        poner_flag(valor)
        expect(described_class.agentes_desde_bd?(account)).to be(true)
      end
    end

    it "es false con un valor no booleano como '0' o 'off'" do
      poner_flag('0')
      expect(described_class.agentes_desde_bd?(account)).to be(false)
    end
  end
end
