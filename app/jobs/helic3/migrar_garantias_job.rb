# frozen_string_literal: true

# MIG-02 (Pieza 4): corre la migración en Sidekiq para que la página no se quede
# esperando. Descarga el CSV subido (ActiveStorage) y se lo pasa al servicio, que
# va dejando el reporte en los Helic3::Migracion::Caso.
class Helic3::MigrarGarantiasJob < ApplicationJob
  queue_as :default
  # una migración o un vaciado que falla se revisa en la página; no se repite solo.
  sidekiq_options retry: false

  def perform(corrida, simulacion:)
    corrida.update!(estado: simulacion ? 'simulando' : 'confirmando', iniciado_at: Time.current)
    # download devuelve el blob en ASCII-8BIT (binario); el CSV es UTF-8 y el lector
    # normaliza Unicode, así que hay que reinterpretar los bytes como UTF-8.
    csv = corrida.archivo.download.force_encoding('UTF-8')
    Helic3::Migracion::ImportarGarantias.new(corrida: corrida, csv: csv, simulacion: simulacion).call
  rescue StandardError => e
    corrida.update(estado: 'fallida', mensaje_error: "#{e.class}: #{e.message}", finalizado_at: Time.current)
    raise e
  end
end
