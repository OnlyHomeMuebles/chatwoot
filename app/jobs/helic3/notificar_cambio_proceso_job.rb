# frozen_string_literal: true

# COR-02: se encola DESPUES de la transaccion que avanza el proceso (ver
# Helic3::Casos::AvanzarGarantia) -- si el commit no ocurre, este job nunca se
# encola, y por tanto nunca sale un correo de una transicion que se revirtio.
class Helic3::NotificarCambioProcesoJob < ApplicationJob
  queue_as :default

  def perform(evento_id)
    evento = Helic3::Evento.find_by(id: evento_id)
    return if evento.nil? # el evento pudo borrarse; no hay nada que notificar

    Helic3::Correos::NotificarCambioProceso.call(evento: evento)
  end
end
