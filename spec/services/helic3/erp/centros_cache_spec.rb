# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Erp::CentrosCache do
  let(:adapter) { instance_double(Helic3::Erp::SiesaHubAdapter) }
  let(:respuesta) do
    JSON.parse(File.read(Rails.root.join('spec/fixtures/helic3/centros_operacion_siesa.json')))
  end

  # cache real (no el null_store de test) para poder verificar que SÍ cachea.
  around do |ejemplo|
    cache_previo = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ejemplo.run
  ensure
    Rails.cache = cache_previo
  end

  before { allow(Helic3::Erp).to receive(:adapter).and_return(adapter) }

  it 'trae la lista de Siesa UNA vez y la deja cacheada (no vuelve a llamar)' do
    expect(adapter).to receive(:centros).once.and_return(respuesta)

    primera = described_class.lista
    segunda = described_class.lista

    expect(primera.size).to eq(3)
    expect(segunda).to eq(primera)
  end

  it 'si el adaptador no ofrece centros (nil), devuelve [] y NO cachea (reintenta la próxima)' do
    expect(adapter).to receive(:centros).twice.and_return(nil)

    expect(described_class.lista).to eq([])
    expect(described_class.lista).to eq([])
  end

  # Jhan #173 (bloqueante + opcional): si la consulta de centros FALLA (Siesa caida/lenta/mal
  # configurada), no se propaga -> [] (no tumba cliente+facturas). Y el fallo se cachea un rato
  # para no reintentar (y esperar el timeout) en cada cedula mientras Siesa este caida.
  it 'si la consulta de centros falla, devuelve [] y cachea el fallo (no reintenta en cada cédula)' do
    expect(adapter).to receive(:centros).once.and_raise(Helic3::Erp::NoDisponible)

    expect(described_class.lista).to eq([])
    expect(described_class.lista).to eq([]) # la 2da usa el fallo cacheado: centros se llamó una sola vez
  end
end
