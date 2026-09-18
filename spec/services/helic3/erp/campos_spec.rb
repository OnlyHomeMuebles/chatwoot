# frozen_string_literal: true

require 'rails_helper'

# ERP-07: garantiza que la tabla de campos documentada (ERP_CAMPOS.md) coincide EXACTAMENTE con los
# objetos de valor del contrato. Si alguien cambia un campo en el código sin actualizar el documento
# (o viceversa), esta prueba falla.
RSpec.describe 'ERP-07 · Campos requeridos por consulta' do # rubocop:disable RSpec/DescribeClass
  it 'Customer expone exactamente los campos documentados' do
    expect(Helic3::Erp::Customer.members).to eq(%i[cedula nombre email telefono])
  end

  it 'Invoice expone exactamente los campos documentados' do
    expect(Helic3::Erp::Invoice.members).to eq(%i[numero fecha total saldo estado items])
  end

  it 'AccountStatement expone exactamente los campos documentados' do
    expect(Helic3::Erp::AccountStatement.members).to eq(%i[cedula saldo_total facturas_pendientes al_dia])
  end
end
