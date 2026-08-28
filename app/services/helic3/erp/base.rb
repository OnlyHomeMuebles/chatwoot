# frozen_string_literal: true

# Contrato (puerto) para consultar el ERP Siesa, independiente de quién lo implemente.
# Las implementaciones concretas heredan de esta clase y deben implementar los 4 métodos:
#   - adaptador simulado (ERP-03) para desarrollar sin el API del proveedor
#   - adaptador real (ERP-05) contra el API de Siesa
# El código que consume el ERP depende SIEMPRE de este contrato, nunca de una implementación.
class Helic3::Erp::Base
  # Identifica a un cliente por su número de cédula.
  # @param cedula [String]
  # @return [Helic3::Erp::Customer, nil] el cliente, o nil si no existe
  def find_customer(cedula:)
    raise NotImplementedError, "#{self.class} debe implementar #find_customer(cedula:)"
  end

  # Lista las facturas de un cliente.
  # @param cedula [String]
  # @return [Array<Helic3::Erp::Invoice>]
  def invoices(cedula:)
    raise NotImplementedError, "#{self.class} debe implementar #invoices(cedula:)"
  end

  # Detalle de una factura por su número.
  # @param number [String]
  # @return [Helic3::Erp::Invoice, nil]
  def invoice(number:)
    raise NotImplementedError, "#{self.class} debe implementar #invoice(number:)"
  end

  # Estado de cuenta (cartera / saldo) de un cliente.
  # @param cedula [String]
  # @return [Helic3::Erp::AccountStatement, nil]
  def account_statement(cedula:)
    raise NotImplementedError, "#{self.class} debe implementar #account_statement(cedula:)"
  end
end
