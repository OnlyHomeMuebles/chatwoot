# frozen_string_literal: true

require 'rails_helper'

# ERP-10: la fachada del modulo. Por ahora solo normaliza la cedula; ERP-04 le
# sumara .adapter y .habilitado?.
RSpec.describe Helic3::Erp do
  # GlobalConfig cachea en Redis: se limpia antes y despues para no filtrar el modo (ERP-16).
  around do |ejemplo|
    GlobalConfig.clear_cache
    ejemplo.run
    GlobalConfig.clear_cache
  end

  def configurar(valores)
    valores.each { |clave, valor| InstallationConfig.create!(name: clave, value: valor, locked: false) }
  end

  let(:conexion_siesa) do
    {
      described_class::CLAVE_MODO => 'siesa',
      described_class::CLAVE_BASE_URL => 'https://qa.siesahub.com',
      described_class::CLAVE_CLIENT_ID => 'cid-secreto',
      described_class::CLAVE_CONNI_KEY => 'key-secreta',
      described_class::CLAVE_CONNI_TOKEN => 'tok-secreto',
      described_class::CLAVE_ID_COMPANIA => '1',
      described_class::CLAVE_CONSULTA_CLIENTES => 'API_v2_Terceros',
      described_class::CLAVE_CONSULTA_COMPRAS => 'compras_a, compras_b'
    }
  end

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

  # ERP-04/ERP-16: el interruptor del modulo. El modo de Super Admin (installation_configs,
  # leido por GlobalConfig) decide si se habla con el simulado, con Siesa o con nadie. Por
  # defecto DESACTIVADO.
  describe '.modo y .habilitado?' do
    it 'CA1: sin fila en Super Admin, el modo es desactivado y habilitado? es false' do
      expect(described_class.modo).to eq('desactivado')
      expect(described_class.habilitado?).to be(false)
    end

    it 'habilitado? es true en simulado' do
      configurar(described_class::CLAVE_MODO => 'simulado')
      expect(described_class.habilitado?).to be(true)
    end

    it 'habilitado? es true en siesa' do
      configurar(described_class::CLAVE_MODO => 'siesa')
      expect(described_class.habilitado?).to be(true)
    end

    it 'al cambiar el modo y guardar, aplica en la siguiente consulta sin reiniciar' do
      configurar(described_class::CLAVE_MODO => 'simulado')
      expect(described_class.modo).to eq('simulado')

      InstallationConfig.find_by!(name: described_class::CLAVE_MODO).update!(value: 'desactivado')

      expect(described_class.modo).to eq('desactivado')
    end

    it 'no lee la variable de entorno anterior' do
      with_modified_env HELIC3_ERP_MODO: 'simulado' do
        expect(described_class.modo).to eq('desactivado')
      end
    end
  end

  # ERP-16 (C4): el numero de factura leido de una foto o escrito por el cliente cruza con el del ERP.
  describe '.misma_factura?' do
    it 'cruza el mismo numero en distintos formatos' do
      ['FV-1102', 'FV 0001102', 'fv1102', '1102', '0001102'].each do |leido|
        expect(described_class.misma_factura?('FV-1102', leido)).to be(true), leido
      end
    end

    it 'no cruza otro numero ni otro prefijo' do
      expect(described_class.misma_factura?('FV-1102', 'FV-1103')).to be(false)
      expect(described_class.misma_factura?('FV-1102', 'FE-1102')).to be(false)
    end

    it 'no cruza con un valor vacio o sin forma de factura' do
      expect(described_class.misma_factura?('FV-1102', nil)).to be(false)
      expect(described_class.misma_factura?('FV-1102', 'sin numero')).to be(false)
    end
  end

  describe '.adapter' do
    it 'CA2: en modo simulado devuelve un SimulatedAdapter' do
      configurar(described_class::CLAVE_MODO => 'simulado')
      expect(described_class.adapter).to be_a(Helic3::Erp::SimulatedAdapter)
    end

    it 'en desactivado no entrega adaptador: levanta NoDisponible' do
      configurar(described_class::CLAVE_MODO => 'desactivado')
      # Se compara por class.name (no por la constante): AGENTS.md lo exige para evitar
      # flakes en los shards de CI con recarga de codigo.
      expect { described_class.adapter }.to(raise_error { |e| expect(e.class.name).to eq('Helic3::Erp::NoDisponible') })
    end

    it 'con un modo desconocido levanta ConfiguracionInvalida con mensaje claro' do
      configurar(described_class::CLAVE_MODO => 'otracosa')
      expect { described_class.adapter }.to raise_error do |e|
        expect(e.class.name).to eq('Helic3::Erp::ConfiguracionInvalida')
        expect(e.message).to include('otracosa')
      end
    end

    it 'CA3: en siesa sin ConniToken, nombra la clave que falta y no imprime secretos' do
      configurar(conexion_siesa.except(described_class::CLAVE_CONNI_TOKEN))

      expect { described_class.adapter }.to raise_error do |e|
        expect(e.class.name).to eq('Helic3::Erp::ConfiguracionInvalida')
        expect(e.message).to include('HELIC3_SIESA_HUB_CONNI_TOKEN')
        expect(e.message).not_to include('cid-secreto', 'key-secreta')
      end
    end

    it 'un campo con solo espacios cuenta como vacio' do
      configurar(conexion_siesa.merge(described_class::CLAVE_ID_COMPANIA => '   '))

      expect { described_class.adapter }.to(raise_error { |e| expect(e.message).to include('HELIC3_SIESA_HUB_ID_COMPANIA') })
    end

    it 'CA2 (siesa con todo configurado): arma el SiesaHubAdapter con la conexion de Super Admin' do
      configurar(conexion_siesa)
      allow(Helic3::Erp::SiesaHubCliente).to receive(:new).and_call_original

      expect(described_class.adapter.class.name).to eq('Helic3::Erp::SiesaHubAdapter')
      expect(Helic3::Erp::SiesaHubCliente).to have_received(:new).with(
        base_url: 'https://qa.siesahub.com', client_id: 'cid-secreto', conni_key: 'key-secreta',
        conni_token: 'tok-secreto', id_compania: '1'
      )
    end

    it 'separa las consultas de compras por coma' do
      configurar(conexion_siesa)
      allow(Helic3::Erp::SiesaHubAdapter).to receive(:new).and_call_original

      described_class.adapter

      expect(Helic3::Erp::SiesaHubAdapter).to have_received(:new)
        .with(hash_including(consulta_clientes: 'API_v2_Terceros', consultas_compras: %w[compras_a compras_b]))
    end
  end
end
