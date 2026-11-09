# frozen_string_literal: true

# ERP-16 (C2): un solo camino para guardar en la ficha lo que viene del ERP, sea desde el
# formulario manual o desde el agente de IA: el cliente (RegistrarClienteErp) y la compra
# (RegistrarCompraErp), cruzados contra el cache. Lo que no cruza con Siesa queda con la
# fuente de quien lo escribio: humano desde el formulario, confirmado desde el agente. Asi
# un caso del agente queda con los mismos campos y fuentes que uno del formulario.
class Helic3::Casos::RegistrarDesdeErp
  CAMPOS_CLIENTE = %i[cedula ciudad direccion cliente_nombre cliente_telefono cliente_email].freeze
  CAMPOS_COMPRA = %i[factura_numero factura_fecha productos producto_nombre producto_referencia].freeze

  # datos: los del cliente (CAMPOS_CLIENTE) y los de la compra: factura_numero,
  # factura_fecha, productos ([{nombre:, referencia:}]) y producto_nombre/producto_referencia
  # (lo escrito a mano cuando el producto no esta en la factura).
  def initialize(ticket:, datos:, fuente:)
    @ticket = ticket
    @datos = datos.to_h.symbolize_keys
    @fuente = fuente
  end

  def call
    Helic3::Casos::RegistrarClienteErp.new(ticket: @ticket, datos: @datos.slice(*CAMPOS_CLIENTE),
                                           fuente: @fuente).call

    # El agente puede guardar en varias llamadas (p. ej. despues solo la direccion): sin datos de
    # compra no se toca la compra, para no vaciar los productos que ya quedaron en la ficha.
    compra = @datos.slice(*CAMPOS_COMPRA).compact_blank
    return if compra.empty?

    Helic3::Casos::RegistrarCompraErp.new(ticket: @ticket, cedula: @datos[:cedula], fuente: @fuente,
                                          datos: compra).call
  end
end
