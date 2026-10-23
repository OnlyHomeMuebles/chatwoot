# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::ImportarFacturasJob, type: :job do
  let(:account) { create(:account) }

  def crear_carga
    carga = Helic3::Carga.create!(account: account, tipo: 'facturas', modo: 'anexar',
                                  nombre_archivo: 'facturas.csv', estado: 'procesando')
    carga.archivo.attach(
      io: StringIO.new("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-001,Cali,2026-09-01,100000\n"),
      filename: 'facturas.csv', content_type: 'text/csv'
    )
    carga
  end

  it 'procesa la carga y la deja completada' do
    carga = crear_carga

    described_class.perform_now(carga_id: carga.id)

    expect(carga.reload).to have_attributes(estado: 'completado', filas_insertadas: 1)
  end

  it 'no revienta si la carga ya no existe' do
    expect { described_class.perform_now(carga_id: -1) }.not_to raise_error
  end

  # Revision de Jhan (PR #140): si algo revienta durante el procesamiento (un
  # archivo corrupto, un error de infraestructura), la carga debe quedar
  # marcada "fallido" en vez de atascada en "procesando" para siempre.
  it 'marca la carga como "fallido" si el procesamiento revienta' do
    carga = crear_carga
    allow(Helic3::Cargas::ImportarFacturas).to receive(:call).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(carga_id: carga.id) }.not_to raise_error

    expect(carga.reload.estado).to eq('fallido')
  end
end
