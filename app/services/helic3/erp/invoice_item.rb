# frozen_string_literal: true

# Ítem (producto) de una factura del ERP. Objeto de valor inmutable.
# `referencia` es el código del producto en el ERP: va a la ficha como producto_referencia
# (ERP-15) y, al abrir la garantía, cada ítem elegido se vuelve un ítem de la garantía.
Helic3::Erp::InvoiceItem = Data.define(:referencia, :descripcion, :cantidad, :valor)
