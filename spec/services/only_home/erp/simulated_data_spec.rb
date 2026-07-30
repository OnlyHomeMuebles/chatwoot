# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::Erp::SimulatedData do
  it 'tiene varios clientes con cédula única, del tipo del contrato' do
    expect(described_class.customers.values).to all(be_a(OnlyHome::Erp::Customer))
    expect(described_class.cedulas.uniq).to eq(described_class.cedulas)
    expect(described_class.cedulas.size).to be >= 3
  end

  it 'las facturas cubren los tres estados reales (pagada, pendiente, vencida)' do
    estados = described_class.invoices.values.flatten.map(&:estado).uniq
    expect(estados).to include('pagada', 'pendiente', 'vencida')
  end

  it 'representa el caso de un cliente al día y uno en mora' do
    al_dia = described_class.cedulas.map { |c| described_class.statement(c) }.select(&:al_dia)
    en_mora = described_class.cedulas.map { |c| described_class.statement(c) }.reject(&:al_dia)

    expect(al_dia).not_to be_empty
    expect(en_mora).not_to be_empty
  end

  it 'el estado de cuenta es consistente con las facturas del cliente (mezcla)' do
    # Pedro (1098765432): pagada + pendiente(1.5M) + vencida(0.6M) => saldo 2.1M, 2 pendientes, en mora
    statement = described_class.statement('1098765432')

    expect(statement.saldo_total).to eq(2_100_000)
    expect(statement.facturas_pendientes).to eq(2)
    expect(statement.al_dia).to be(false)
  end

  it 'encuentra una factura por su número' do
    expect(described_class.invoice('FV-1050')).to be_a(OnlyHome::Erp::Invoice)
    expect(described_class.invoice('NO-EXISTE')).to be_nil
  end

  it 'devuelve nil en el estado de cuenta de una cédula inexistente' do
    expect(described_class.statement('00000000')).to be_nil
  end
end
