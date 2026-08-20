# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::Erp::SimulatedAdapter do
  subject(:adapter) { described_class.new }

  let(:known_cedula) { '1032456789' }
  let(:known_invoice_number) { 'FV-1001' }

  # Verifica que el adaptador cumple el contrato de ERP-01
  it_behaves_like 'un adaptador de ERP'

  it 'devuelve nil para un cliente inexistente' do
    expect(adapter.find_customer(cedula: '00000000')).to be_nil
  end

  it 'lista las facturas del cliente' do
    expect(adapter.invoices(cedula: known_cedula).map(&:numero)).to include('FV-1001', 'FV-1002')
  end

  it 'devuelve lista vacía de facturas para un cliente inexistente' do
    expect(adapter.invoices(cedula: '00000000')).to eq([])
  end

  it 'entrega el estado de cuenta de un cliente en mora' do
    expect(adapter.account_statement(cedula: '52998877').al_dia).to be(false)
  end
end
