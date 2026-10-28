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

  # ERP-04: el interruptor del modulo. HELIC3_ERP_MODO decide si se habla con el
  # simulado, con Siesa o con nadie. Por defecto DESACTIVADO.
  describe '.modo y .habilitado?' do
    it 'CA1: sin la variable, el modo es desactivado y habilitado? es false' do
      with_modified_env HELIC3_ERP_MODO: nil do
        expect(described_class.modo).to eq('desactivado')
        expect(described_class.habilitado?).to be(false)
      end
    end

    it 'habilitado? es true en simulado y en siesa' do
      with_modified_env HELIC3_ERP_MODO: 'simulado' do
        expect(described_class.habilitado?).to be(true)
      end
      with_modified_env HELIC3_ERP_MODO: 'siesa' do
        expect(described_class.habilitado?).to be(true)
      end
    end
  end

  describe '.adapter' do
    it 'CA2: en modo simulado devuelve un SimulatedAdapter' do
      with_modified_env HELIC3_ERP_MODO: 'simulado' do
        expect(described_class.adapter).to be_a(Helic3::Erp::SimulatedAdapter)
      end
    end

    it 'en desactivado no entrega adaptador: levanta NoDisponible' do
      with_modified_env HELIC3_ERP_MODO: 'desactivado' do
        # Se compara por class.name (no por la constante): AGENTS.md lo exige para evitar
        # flakes en los shards de CI con recarga de codigo.
        expect { described_class.adapter }.to raise_error { |e| expect(e.class.name).to eq('Helic3::Erp::NoDisponible') }
      end
    end

    it 'con un modo desconocido levanta ConfiguracionInvalida con mensaje claro' do
      with_modified_env HELIC3_ERP_MODO: 'otracosa' do
        expect { described_class.adapter }.to raise_error do |e|
          expect(e.class.name).to eq('Helic3::Erp::ConfiguracionInvalida')
          expect(e.message).to include('otracosa')
        end
      end
    end

    it 'CA3: en siesa sin SIESA_HUB_CONNI_TOKEN, nombra la variable y no imprime secretos' do
      with_modified_env HELIC3_ERP_MODO: 'siesa',
                        SIESA_HUB_BASE_URL: 'https://qa.siesahub.com',
                        SIESA_HUB_CLIENT_ID: 'cid-secreto', SIESA_HUB_CONNI_KEY: 'key-secreta',
                        SIESA_HUB_CONNI_TOKEN: nil,
                        SIESA_HUB_ID_COMPANIA: '1', SIESA_HUB_CONSULTA_COMPRAS: 'compras' do
        expect { described_class.adapter }.to raise_error do |e|
          expect(e.class.name).to eq('Helic3::Erp::ConfiguracionInvalida')
          expect(e.message).to include('SIESA_HUB_CONNI_TOKEN')
          expect(e.message).not_to include('cid-secreto', 'key-secreta')
        end
      end
    end

    it 'CA2 (siesa con todo configurado): devuelve un SiesaHubAdapter' do
      with_modified_env HELIC3_ERP_MODO: 'siesa',
                        SIESA_HUB_BASE_URL: 'https://qa.siesahub.com',
                        SIESA_HUB_CLIENT_ID: 'cid', SIESA_HUB_CONNI_KEY: 'key',
                        SIESA_HUB_CONNI_TOKEN: 'tok', SIESA_HUB_ID_COMPANIA: '1',
                        SIESA_HUB_CONSULTA_COMPRAS: 'compras' do
        expect(described_class.adapter.class.name).to eq('Helic3::Erp::SiesaHubAdapter')
      end
    end
  end
end
