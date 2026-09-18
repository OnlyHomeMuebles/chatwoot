# frozen_string_literal: true

# GAR-03: mueve un producto de proceso y, si con eso todos los productos del
# radicado quedaron resueltos, cierra la garantia. Servicio DELGADO a proposito:
# la maquina de estados ya vive en los modelos (GarantiaItem#avanzar_a! sella
# resuelto_at en procesos terminales; Garantia#cerrar! solo cierra si resuelta?).
# Aqui solo se orquesta el orden —avanzar, luego intentar cerrar— en una sola
# transaccion, sin reimplementar ninguna de esas reglas.
class Helic3::Casos::AvanzarGarantia
  def initialize(item:, proceso:, decision: nil)
    @item = item
    @proceso = proceso
    @decision = decision
  end

  def call
    Helic3::Garantia.transaction do
      @item.avanzar_a!(@proceso, decision: @decision)

      garantia = @item.garantia
      garantia.items.reload # el item que avanzo ya esta persistido; releer para que cerrar! vea el estado real
      garantia.cerrar!      # no-op si aun quedan items pendientes (lo protege el modelo)
      garantia
    end
  end
end
