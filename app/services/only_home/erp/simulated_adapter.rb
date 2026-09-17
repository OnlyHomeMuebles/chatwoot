# frozen_string_literal: true

# Adaptador simulado del ERP (ERP-03): implementa el contrato `OnlyHome::Erp::Base` leyendo los
# datos simulados (ERP-02). Permite desarrollar y probar TODO el módulo sin el API de Siesa.
class OnlyHome::Erp::SimulatedAdapter < OnlyHome::Erp::Base
  def find_customer(cedula:)
    OnlyHome::Erp::SimulatedData.customer(cedula)
  end

  def invoices(cedula:)
    OnlyHome::Erp::SimulatedData.invoices_for(cedula)
  end

  def invoice(number:)
    OnlyHome::Erp::SimulatedData.invoice(number)
  end

  def account_statement(cedula:)
    OnlyHome::Erp::SimulatedData.statement(cedula)
  end
end
