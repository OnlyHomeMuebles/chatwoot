# frozen_string_literal: true

# Contrato que TODO adaptador de ERP debe cumplir (simulado ERP-03, real ERP-05).
# Uso en el spec de un adaptador:
#   subject(:adapter) { described_class.new }
#   let(:known_cedula) { '...' }          # una cédula que exista en el adaptador
#   let(:known_invoice_number) { '...' }  # un número de factura que exista
#   it_behaves_like 'un adaptador de ERP'
RSpec.shared_examples 'un adaptador de ERP' do
  it 'implementa las 4 consultas del contrato' do
    expect(adapter).to respond_to(:find_customer, :invoices, :invoice, :account_statement)
  end

  it 'find_customer devuelve un Customer para una cédula conocida' do
    customer = adapter.find_customer(cedula: known_cedula)
    expect(customer).to be_a(OnlyHome::Erp::Customer)
    expect(customer.cedula).to eq(known_cedula)
  end

  it 'invoices devuelve una lista de facturas del cliente' do
    expect(adapter.invoices(cedula: known_cedula)).to all(be_a(OnlyHome::Erp::Invoice))
  end

  it 'invoice devuelve el detalle de una factura conocida' do
    expect(adapter.invoice(number: known_invoice_number)).to be_a(OnlyHome::Erp::Invoice)
  end

  it 'account_statement devuelve el estado de cuenta del cliente' do
    expect(adapter.account_statement(cedula: known_cedula)).to be_a(OnlyHome::Erp::AccountStatement)
  end
end
