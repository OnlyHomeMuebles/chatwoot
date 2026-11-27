# frozen_string_literal: true

# MIG-02 (sección 5.2): corre el vaciado del cuarto de PQR en Sidekiq. El borrado
# con destroy PQR por PQR puede tardar, así que la página no se queda esperando.
class Helic3::VaciarCasosJob < ApplicationJob
  queue_as :default

  def perform(corrida)
    corrida.update!(estado: 'confirmando', iniciado_at: Time.current)
    Helic3::Migracion::VaciarCasos.call(corrida: corrida)
  rescue StandardError => e
    corrida.update(estado: 'fallida', finalizado_at: Time.current)
    raise e
  end
end
