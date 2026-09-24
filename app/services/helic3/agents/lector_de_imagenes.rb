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
  # tesseract corre como proceso externo (shell-out): sin tope, una imagen
  # compleja o corrupta puede colgar el worker de Sidekiq indefinidamente.
  TIMEOUT_OCR = 15

  def self.leer(urls)
    new.leer(urls)
  end

  # nil si no hay imagenes, o si ninguna trae texto legible; el texto unido
  # (varias imagenes, separadas) si encuentra algo. Una imagen que falla
  # (descarga, formato corrupto, timeout) NUNCA debe descartar el texto que sí
  # se pudo leer de las demás -- por eso cada una corre en su propio rescue,
  # no uno solo alrededor de todo el lote.
  def leer(urls)
    return nil if urls.blank?

    textos = urls.filter_map { |url| leer_texto_seguro(url) }
    textos.presence&.join("\n---\n")
  end

  private

  def leer_texto_seguro(url)
    leer_texto(url).presence
  rescue StandardError => e
    Rails.logger.error("[Helic3] lector_de_imagenes fallo con #{url}: #{e.class}: #{e.message}")
    nil
  end

  # SafeFetch (ya usado en el resto del repo para URLs externas) filtra SSRF y
  # restringe el content-type a imagen; Down.download crudo no tenia ninguna
  # de las dos protecciones y la URL puede venir de un canal externo
  # (Attachment#external_url en WhatsApp/Instagram/Messenger no es un dominio
  # propio de Chatwoot).
  def leer_texto(url)
    SafeFetch.fetch(url, allowed_content_type_prefixes: ['image/'], read_timeout: TIMEOUT_DESCARGA) do |archivo|
      Timeout.timeout(TIMEOUT_OCR) { RTesseract.new(archivo.tempfile.path, lang: IDIOMA).to_s.strip }
    end
  end
end
