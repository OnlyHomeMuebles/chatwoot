# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Migracion::Corrida do
  let(:account) { create(:account) }

  it 'guarda una corrida de migración con sus totales en cero' do
    corrida = described_class.create!(account: account, tipo: 'migracion')
    expect(corrida).to be_persisted
    expect(corrida.estado).to eq('pendiente')
    expect(corrida.total_ok).to eq(0)
    expect(corrida.casos).to be_empty
  end

  it 'rechaza un tipo que no sea vaciado ni migracion' do
    expect { described_class.create!(account: account, tipo: 'otro') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rechaza un estado desconocido' do
    expect { described_class.create!(account: account, tipo: 'vaciado', estado: 'inventado') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'agrupa sus casos y los borra en cascada' do
    corrida = described_class.create!(account: account, tipo: 'migracion', estado: 'simulado')
    corrida.casos.create!(account: account, consecutivo: 3182, resultado: 'ok', simulacion: true)

    expect(corrida.casos.count).to eq(1)
    expect { corrida.destroy }.to change(Helic3::Migracion::Caso, :count).from(1).to(0)
  end

  it 'acepta el archivo adjunto (ActiveStorage)' do
    corrida = described_class.create!(account: account, tipo: 'migracion')
    corrida.archivo.attach(io: StringIO.new('consecutivo,cliente\n3182,Ana'), filename: 'datagrid.csv',
                           content_type: 'text/csv')
    expect(corrida.archivo).to be_attached
  end
end

RSpec.describe Helic3::Migracion::Caso do
  let(:account) { create(:account) }
  let(:corrida) { Helic3::Migracion::Corrida.create!(account: account, tipo: 'migracion', estado: 'simulado') }

  it 'no permite el mismo consecutivo dos veces en la misma corrida (idempotencia)' do
    corrida.casos.create!(account: account, consecutivo: 100, resultado: 'ok', simulacion: true)
    repetido = corrida.casos.build(account: account, consecutivo: 100, resultado: 'omitido', simulacion: true)

    expect(repetido).not_to be_valid
    expect(repetido.errors[:consecutivo]).to be_present
  end

  it 'sí permite el mismo consecutivo en corridas distintas' do
    otra = Helic3::Migracion::Corrida.create!(account: account, tipo: 'migracion', estado: 'simulado')
    corrida.casos.create!(account: account, consecutivo: 100, resultado: 'ok', simulacion: true)

    expect { otra.casos.create!(account: account, consecutivo: 100, resultado: 'ok', simulacion: true) }
      .not_to raise_error
  end

  it 'rechaza un resultado fuera de ok/omitido/fallido' do
    caso = corrida.casos.build(account: account, consecutivo: 1, resultado: 'raro', simulacion: true)
    expect(caso).not_to be_valid
  end
end
