# frozen_string_literal: true

# Factura del ERP. Objeto de valor inmutable.
# `estado` p. ej. "pagada" | "pendiente" | "vencida". `centro_operacion` es el id de la tienda
# (C.O.) donde se facturó: se muestra en el selector (ERP-15) y cruza la garantía con
# helic3_facturas_venta (IND-08). `centro_operacion_compania` (ERP-18b) es la compañía de la
# factura: el mismo id de C.O. es una tienda distinta según la compañía, así que el nombre del
# C.O. se resuelve por compañía + id. `items` es el detalle de líneas (InvoiceItem), opcional.
Helic3::Erp::Invoice = Data.define(:numero, :fecha, :total, :saldo, :estado,
                                   :centro_operacion, :centro_operacion_compania,
                                   :centro_operacion_nombre, :items) do
  def initialize(numero:, fecha:, total:, saldo:, estado:, centro_operacion: nil,
                 centro_operacion_compania: nil, centro_operacion_nombre: nil, items: [])
    super
  end
end
