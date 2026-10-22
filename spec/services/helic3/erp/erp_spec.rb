# frozen_string_literal: true

require 'rails_helper'

# ERP-10: la fachada del modulo. Por ahora solo normaliza la cedula; ERP-04 le
# sumara .adapter y .habilitado?.
RSpec.describe Helic3::Erp do
  describe '.normalizar_cedula' do
    it 'quita puntos y espacios y deja solo digitos' do
      expect(described_class.normalizar_cedula('1.032.456.789')).to eq('1032456789')
      expect(described_class.normalizar_cedula('  1032456789  ')).to eq('1032456789')
    end

    it 'descarta el digito de verificacion que viene despues del guion' do
      expect(described_class.normalizar_cedula('900.123.456-7')).to eq('900123456')
    end

    it 'no corta la cedula por un guion que no sea el del DV (separador)' do
      expect(described_class.normalizar_cedula('900-123-456')).to eq('900123456')
    end

    it 'devuelve nil si quedan menos de 5 digitos' do
      expect(described_class.normalizar_cedula('123')).to be_nil
    end

    it 'devuelve nil si quedan mas de 15 digitos' do
      expect(described_class.normalizar_cedula('1234567890123456')).to be_nil
    end

    it 'devuelve nil cuando no hay digitos (letras o vacio)' do
      expect(described_class.normalizar_cedula('abc')).to be_nil
      expect(described_class.normalizar_cedula('')).to be_nil
      expect(described_class.normalizar_cedula(nil)).to be_nil
    end
  end
end
