# frozen_string_literal: true

# GAR-03: mueve un producto de proceso y, si con eso todos los productos del
# radicado quedaron resueltos, cierra la garantia. Servicio DELGADO a proposito:
# la maquina de estados ya vive en los modelos (GarantiaItem#avanzar_a! sella
# resuelto_at en procesos terminales; Garantia#cerrar! solo cierra si resuelta?).
# Aqui solo se orquesta el orden —avanzar, luego intentar cerrar— en una sola
# transaccion, sin reimplementar ninguna de esas reglas.
#
# GAR-08: cuando el movimiento CIERRA el radicado, la observacion de cierre es
# obligatoria. La regla vive aqui (no solo en el modal): si cierra sin texto se
# levanta ObservacionRequerida y la transaccion revierte el avance, asi que el
# producto NO se mueve (CA#4). Con texto, se guarda la observacion con su autor y
# fecha y se registra el evento garantia_finalizada en la bitacora.
class Helic3::Casos::AvanzarGarantia
  # el controlador la traduce a 422: cerrar un radicado exige observacion.
  class ObservacionRequerida < StandardError; end

  def initialize(item:, proceso:, decision: nil, observacion: nil, usuario: nil)
    @item = item
    @proceso = proceso
    @decision = decision
    @observacion = observacion
    @usuario = usuario
  end

  def call
    Helic3::Garantia.transaction do
      @item.avanzar_a!(@proceso, decision: @decision)

      garantia = @item.garantia
      garantia.items.reload # el item que avanzo ya esta persistido; releer para que resuelta? vea el estado real

      finalizar!(garantia) if garantia.resuelta? # este movimiento cerro el radicado
      garantia
    end
  end

  private

  # cierra el radicado con su observacion obligatoria. Todo dentro de la misma
  # transaccion de #call: si el texto falta, el raise revierte tambien el avance.
  def finalizar!(garantia)
    texto = @observacion.to_s.strip
    raise ObservacionRequerida, 'La observacion de cierre es obligatoria' if texto.blank?

    garantia.cerrar! # no-op si ya estaba cerrada; sella cerrada_at
    garantia.anexar_observacion_cierre!(texto, @usuario)
    Helic3::Evento.registrar!(ticket: garantia.ticket, tipo: 'garantia_finalizada',
                              origen: 'humano', actor: @usuario, garantia: garantia,
                              payload: { observacion: texto })
  end
end
