# frozen_string_literal: true

# MIG-02 (sección 5.2): corre el vaciado del cuarto de PQR en Sidekiq. El borrado
# con destroy PQR por PQR puede tardar, así que la página no se queda esperando.
class Helic3::VaciarCasosJob < ApplicationJob
  queue_as :default
  # una migración o un vaciado que falla se revisa en la página; no se repite solo.
  sidekiq_options retry: false

  def perform(corrida)
    corrida.update!(estado: 'confirmando', iniciado_at: Time.current)
    Helic3::Migracion::VaciarCasos.call(corrida: corrida)
  rescue StandardError => e
    corrida.update(estado: 'fallida', mensaje_error: "#{e.class}: #{e.message}", finalizado_at: Time.current)
    raise e
  end
end
