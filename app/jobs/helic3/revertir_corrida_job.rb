# frozen_string_literal: true

# MIG-02 (regla 7): revierte una migración en Sidekiq; borrar miles de PQR con
# destroy puede tardar. Si falla, la corrida vuelve a 'completada' con el error.
class Helic3::RevertirCorridaJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(corrida)
    Helic3::Migracion::RevertirCorrida.call(corrida: corrida)
  rescue StandardError => e
    corrida.update(estado: 'completada', mensaje_error: "No se pudo revertir: #{e.class}: #{e.message}")
    raise e
  end
end
