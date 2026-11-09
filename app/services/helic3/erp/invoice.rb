# frozen_string_literal: true

# Factura del ERP. Objeto de valor inmutable.
# `estado` p. ej. "pagada" | "pendiente" | "vencida". `centro_operacion` es la tienda (C.O.)
# donde se facturó: se muestra en el selector (ERP-15) y cruza la garantía con helic3_facturas_venta
# (IND-08). `items` es el detalle de líneas (InvoiceItem), opcional.
Helic3::Erp::Invoice = Data.define(:numero, :fecha, :total, :saldo, :estado, :centro_operacion, :items) do
  def initialize(numero:, fecha:, total:, saldo:, estado:, centro_operacion: nil, items: [])
    super
  end
end
