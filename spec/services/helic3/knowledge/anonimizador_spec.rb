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

    it 'enmascara la cedula escrita con puntos' do
      expect(described_class.call('CC 1.032.456.789')).not_to include('456')
    end

    it 'enmascara el telefono, con y sin espacios' do
      expect(described_class.call('Mi celular es 3009998888')).not_to include('3009998888')
      expect(described_class.call('Llamame al 300 999 8888')).not_to include('300 999 8888')
    end

    it 'enmascara el numero de factura junto a su palabra clave' do
      expect(described_class.call('La factura 345670 salio mal')).not_to include('345670')
    end

    describe 'direccion: consume la nomenclatura completa en los formatos reales' do
      formatos = [
        'Calle 123 # 45-67',
        'cra 43A # 12-34',
        'Cra 43 A No 12-34',
        'Calle 10 Sur # 45-67',
        'Carrera 48 # 10 B - 25'
      ]

      formatos.each do |direccion|
        it "enmascara por completo '#{direccion}'" do
          expect(described_class.call(direccion)).to eq('[direccion]')
        end

        it "no deja restos de '#{direccion}' dentro de una frase" do
          resultado = described_class.call("Vivo en la #{direccion} con mi familia")
          expect(resultado).to include('[direccion]')
          # ningun numero de la direccion sobrevive
          direccion.scan(/\d+/).each { |n| expect(resultado).not_to include(n) }
        end
      end

      it 'enmascara al menos el numero de unidad cuando no hay palabra de via' do
        resultado = described_class.call('Vivo en el conjunto Torres del Parque, apto 502, Envigado')
        expect(resultado).not_to include('502')
      end
    end

    describe 'nombres: enmascara los literales exactos del titular y del asesor' do
      it 'enmascara el nombre completo y sus partes' do
        texto = 'Cliente: Hola, soy Maria Fernanda Gomez Restrepo y mi sofa llego roto'
        resultado = described_class.call(texto, nombres: ['Maria Fernanda Gomez Restrepo', 'Laura Rojas'])

        expect(resultado).to include('[nombre]')
        %w[Maria Fernanda Gomez Restrepo].each { |parte| expect(resultado).not_to include(parte) }
      end

      it 'atrapa una mencion suelta del nombre mas adelante en el hilo' do
        texto = 'Asesor: Con gusto Fernanda, ya reviso tu caso'
        resultado = described_class.call(texto, nombres: ['Maria Fernanda Gomez'])
        expect(resultado).not_to include('Fernanda')
      end
    end

    describe 'preserva la voz que NO identifica al titular' do
      it 'conserva los radicados de PQR' do
        expect(described_class.call('Tu caso quedo con el radicado PQR-2026-00123'))
          .to include('PQR-2026-00123')
      end

      it 'conserva los precios con simbolo o con "pesos"' do
        expect(described_class.call('El sofa cuesta $1.250.000')).to include('1.250.000')
        expect(described_class.call('Son 1.250.000 pesos')).to include('1.250.000')
      end

      it 'no confunde TV con transversal en una muebleria' do
        resultado = described_class.call('El TV 55 pulgadas quedo perfecto')
        expect(resultado).not_to include('[direccion]')
        expect(resultado).to include('TV 55')
      end
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
