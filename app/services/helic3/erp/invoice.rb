# frozen_string_literal: true

# Factura del ERP. Objeto de valor inmutable.
# `estado` p. ej. "pagada" | "pendiente" | "vencida". `items` es el detalle de líneas (opcional).
Helic3::Erp::Invoice = Data.define(:numero, :fecha, :total, :saldo, :estado, :items) do
  def initialize(numero:, fecha:, total:, saldo:, estado:, items: [])
    super
  end
end
