# frozen_string_literal: true

# IND-03 (parcial), revision de Jhan (PR #140): el procesamiento del CSV de
# facturas corre aqui, fuera de la peticion que lo sube -- un archivo real
# trae ~33.000 filas, demasiado para resolverse dentro de un request/response.
# El controlador ya crea la Carga (estado "procesando") y adjunta el archivo
# antes de encolar; aqui solo queda invocar al servicio sobre esa Carga.
class Helic3::ImportarFacturasJob < ApplicationJob
  queue_as :low

  def perform(carga_id:)
    carga = Helic3::Carga.find_by(id: carga_id)
    return if carga.nil?

    Helic3::Cargas::ImportarFacturas.call(carga: carga)
  rescue StandardError => e
    # El servicio ya marca "fallido" en su propio rescue; esto es la red de
    # seguridad si revienta antes de eso (ej. find_by de arriba) o en un punto
    # que el servicio no cubrio.
    carga&.update!(estado: 'fallido')
    Rails.logger.error("[Helic3] importar_facturas carga=#{carga_id}: #{e.class}: #{e.message}")
  end
end
