# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::Erp::Base do
  subject(:adapter) { described_class.new }

  it 'define las 4 consultas del contrato y exige que la implementación las provea' do
    expect { adapter.find_customer(cedula: '123') }.to raise_error(NotImplementedError)
    expect { adapter.invoices(cedula: '123') }.to raise_error(NotImplementedError)
    expect { adapter.invoice(number: 'F-001') }.to raise_error(NotImplementedError)
    expect { adapter.account_statement(cedula: '123') }.to raise_error(NotImplementedError)
  end

  describe 'objetos de valor del contrato' do
    it 'Customer expone los datos del cliente (email/teléfono opcionales)' do
      customer = OnlyHome::Erp::Customer.new(cedula: '1032456789', nombre: 'Ana Ruiz')

      expect(customer.cedula).to eq('1032456789')
      expect(customer.nombre).to eq('Ana Ruiz')
      expect(customer.email).to be_nil
    end

    it 'Invoice expone los datos de la factura (items por defecto vacío)' do
      invoice = OnlyHome::Erp::Invoice.new(numero: 'F-001', fecha: '2026-07-01', total: 100_000, saldo: 0, estado: 'pagada')

      expect(invoice.numero).to eq('F-001')
      expect(invoice.estado).to eq('pagada')
      expect(invoice.items).to eq([])
    end

    it 'AccountStatement expone el saldo y la cartera del cliente' do
      statement = OnlyHome::Erp::AccountStatement.new(cedula: '1032456789', saldo_total: 250_000, facturas_pendientes: 2, al_dia: false)

      expect(statement.saldo_total).to eq(250_000)
      expect(statement.facturas_pendientes).to eq(2)
      expect(statement.al_dia).to be(false)
    end
  end
end
