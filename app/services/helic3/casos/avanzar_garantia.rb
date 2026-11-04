# frozen_string_literal: true

# GAR-03: mueve un producto de proceso y, si con eso todos los productos del
# radicado quedaron resueltos, cierra la garantia. Servicio DELGADO a proposito:
# la maquina de estados ya vive en los modelos (GarantiaItem#avanzar_a! sella
# resuelto_at en procesos terminales; Garantia#cerrar! solo cierra si resuelta?).
# Aqui solo se orquesta el orden —avanzar, luego intentar cerrar— en una sola
# transaccion, sin reimplementar ninguna de esas reglas.
#
# COR-02: registra proceso_avanzado SOLO si el proceso de verdad cambio (mover
# al mismo proceso dos veces no duplica evento ni correo), y encola el aviso al
# cliente DESPUES de la transaccion -- si el commit no ocurre, no sale correo.
class Helic3::Casos::AvanzarGarantia
  def initialize(item:, proceso:, decision: nil, actor: nil, origen: :humano)
    @item = item
    @proceso = proceso
    @decision = decision
    @actor = actor
    @origen = origen
  end

  def call
    proceso_anterior_id = @item.proceso_id
    garantia = nil
    evento = nil

    Helic3::Garantia.transaction do
      @item.avanzar_a!(@proceso, decision: @decision)

      garantia = @item.garantia
      garantia.items.reload # el item que avanzo ya esta persistido; releer para que cerrar! vea el estado real
      garantia.cerrar!      # no-op si aun quedan items pendientes (lo protege el modelo)

      evento = registrar_evento(garantia, proceso_anterior_id) if proceso_anterior_id != @proceso.id
    end

    Helic3::NotificarCambioProcesoJob.perform_later(evento.id) if evento
    garantia
  end

  private

  def registrar_evento(garantia, proceso_anterior_id)
    Helic3::Evento.registrar!(
      ticket: garantia.ticket, tipo: 'proceso_avanzado', origen: @origen, actor: @actor, garantia: garantia,
      payload: { item_id: @item.id, proceso_id: @proceso.id, proceso_anterior_id: proceso_anterior_id }
    )
  end
end
