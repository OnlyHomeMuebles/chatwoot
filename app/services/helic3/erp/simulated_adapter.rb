# frozen_string_literal: true

# Adaptador simulado del ERP (ERP-03): implementa el contrato `Helic3::Erp::Base` leyendo los
# datos simulados (ERP-02). Permite desarrollar y probar TODO el módulo sin el API de Siesa.
class Helic3::Erp::SimulatedAdapter < Helic3::Erp::Base
  def find_customer(cedula:)
    Helic3::Erp::SimulatedData.customer(cedula)
  end

  def invoices(cedula:)
    Helic3::Erp::SimulatedData.invoices_for(cedula)
  end

  def invoice(number:)
    Helic3::Erp::SimulatedData.invoice(number)
  end

  def account_statement(cedula:)
    Helic3::Erp::SimulatedData.statement(cedula)
  end
end
