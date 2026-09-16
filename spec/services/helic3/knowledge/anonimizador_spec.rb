# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Knowledge::Anonimizador do
  describe '.call' do
    it 'enmascara el correo electronico' do
      texto = 'Escribeme a juan.perez@gmail.com cuando puedas'
      expect(described_class.call(texto)).to eq('Escribeme a [correo] cuando puedas')
    end

    it 'enmascara la cedula' do
      expect(described_class.call('Mi cedula es 1032456789')).not_to include('1032456789')
    end

    it 'enmascara el telefono' do
      expect(described_class.call('Mi celular es 3009998888')).not_to include('3009998888')
    end

    it 'enmascara el telefono aunque venga con espacios' do
      expect(described_class.call('Llamame al 300 999 8888')).not_to include('300 999 8888')
    end

    it 'enmascara la direccion con nomenclatura urbana' do
      resultado = described_class.call('Vivo en la Calle 123 # 45-67 con mi familia')
      expect(resultado).to include('[direccion]')
      expect(resultado).not_to include('45-67')
    end

    it 'enmascara el numero de factura junto a su palabra clave' do
      expect(described_class.call('La factura 345670 salio mal')).not_to include('345670')
    end

    it 'deja intacto el dialogo sin datos personales' do
      texto = 'Con gusto te ayudo con la garantia de tu sofa, cuentame que paso'
      expect(described_class.call(texto)).to eq(texto)
    end

    it 'no revienta con nil ni con vacio' do
      expect(described_class.call(nil)).to eq('')
      expect(described_class.call('')).to eq('')
    end
  end
end
