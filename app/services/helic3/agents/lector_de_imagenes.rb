# frozen_string_literal: true

# AGT-08: lee el texto de las fotos que el cliente adjunta, con el motor local
# `tesseract` (gem rtesseract) — sin API, sin key, sin costo por uso.
#
# Corre DETERMINISTA como paso previo del job (ProcessConversationJob), no como
# una tool que el modelo deba acordarse de llamar — el mismo espiritu que
# AGT-06/AGT-07, que tampoco dejan en manos del LLM algo que debe pasar SIEMPRE
# que hay una foto. Probando la version anterior (una tool "analizar_imagen"
# que el agente debia invocar) se comprobo en vivo que el modelo a veces
# responde "no tiene texto legible" SIN haber llamado la tool — inventa el
# resultado. Un bot de atencion al cliente no puede alucinar que revisó una
# evidencia. Por eso el texto se lee siempre y se inyecta ya resuelto en las
# instrucciones del agente (ver PqrsAgent.contextual_instructions): el modelo
# nunca decide si "vale la pena" mirar la foto, ya la tiene leida.
#
# Limite real y deliberado: SOLO lee texto legible (un numero de factura, una
# cedula). No describe objetos, colores ni daños visuales — eso es entender
# una imagen, no reconocimiento de texto, y ningun motor local/gratuito lo hace
# hoy. Quien consuma el resultado no debe prometer mas de lo que da.
#
# Requisito de infraestructura (no de Ruby): el binario `tesseract` debe estar
# instalado en el servidor, con el paquete del idioma que se vaya a leer
# (brew install tesseract && descargar spa.traineddata en desarrollo;
# apt-get install tesseract-ocr tesseract-ocr-spa en produccion/Docker).
class Helic3::Agents::LectorDeImagenes
  IDIOMA = ENV.fetch('OCR_IDIOMA', 'spa')
  # Evita que una imagen enorme o una descarga lenta trabe el job del agente.
  TIMEOUT_DESCARGA = 10

  def self.leer(urls)
    new.leer(urls)
  end

  # nil si no hay imagenes, o si ninguna trae texto legible; el texto unido
  # (varias imagenes, separadas) si encuentra algo.
  def leer(urls)
    return nil if urls.blank?

    textos = urls.filter_map { |url| leer_texto(url).presence }
    textos.presence&.join("\n---\n")
  rescue StandardError => e
    Rails.logger.error("[Helic3] lector_de_imagenes fallo: #{e.class}: #{e.message}")
    nil
  end

  private

  def leer_texto(url)
    archivo = Down.download(url, max_size: 15 * 1024 * 1024, read_timeout: TIMEOUT_DESCARGA)
    RTesseract.new(archivo.path, lang: IDIOMA).to_s.strip
  ensure
    archivo&.close
    archivo&.unlink
  end
end
