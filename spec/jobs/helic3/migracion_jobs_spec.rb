# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::VaciarCasosJob do
  let(:account) { create(:account) }
  let(:corrida) { Helic3::Migracion::Corrida.create!(account: account, tipo: 'vaciado', estado: 'pendiente') }

  it 'marca la corrida en curso y llama al servicio de vaciado' do
    expect(Helic3::Migracion::VaciarCasos).to receive(:call).with(corrida: corrida)

    described_class.new.perform(corrida)

    expect(corrida.reload.estado).to eq('confirmando')
  end
end

RSpec.describe Helic3::MigrarGarantiasJob do
  let(:account) { create(:account) }
  let(:corrida) { Helic3::Migracion::Corrida.create!(account: account, tipo: 'migracion', estado: 'pendiente') }

  it 'descarga el CSV del adjunto y llama al importador con la simulación pedida' do
    corrida.archivo.attach(io: StringIO.new('contenido-csv'), filename: 'd.csv', content_type: 'text/csv')
    servicio = instance_double(Helic3::Migracion::ImportarGarantias, call: corrida)
    expect(Helic3::Migracion::ImportarGarantias).to receive(:new)
      .with(corrida: corrida, csv: 'contenido-csv', simulacion: true).and_return(servicio)

    described_class.new.perform(corrida, simulacion: true)
  end
end
