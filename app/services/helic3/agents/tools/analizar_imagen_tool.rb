# frozen_string_literal: true

# AGT-08: la herramienta con la que el agente LEE el texto de las fotos que el
# cliente adjunta en el chat (el número de una factura, una orden, una cédula).
# Es OCR real con el motor local `tesseract` (gem rtesseract) — sin API, sin key,
# sin costo por uso. Por eso mismo tiene un límite real y deliberado: SOLO lee
# texto legible. No describe objetos, colores ni daños visuales (una pata rota,
# un rayón) — eso es "entender una imagen", no reconocimiento de texto, y ningún
# motor local/gratuito lo hace hoy. El prompt del agente no promete lo que la
# tool no puede dar.
#
# No compite con el paso 5 de PqrsAgent (radicar de inmediato, sin esperar
# fotos): esta tool no bloquea ni retrasa radicar_pqr, solo lee lo que ya llego.
#
# Como el resto de las tools de dominio, esta NO clasifica ni decide nada por su
# cuenta: solo traduce la imagen a texto plano para que el agente siga
# razonando y use radicar_pqr/resolver_pqr como siempre.
#
# Las imagenes NO se piden a la Application API: WebhookHandler ya las extrae del
# payload del propio evento (Message#webhook_data trae la url de cada adjunto) y
# ProcessConversationJob las deja en tool_context.state[:imagenes] antes de correr
# el agente — esta tool solo las lee de ahi.
#
# Requisito de infraestructura (no de Ruby): el binario `tesseract` debe estar
# instalado en el servidor, con el paquete del idioma que se vaya a leer
# (brew install tesseract && descargar spa.traineddata en desarrollo;
# apt-get install tesseract-ocr tesseract-ocr-spa en produccion/Docker).
class Helic3::Agents::Tools::AnalizarImagenTool < Helic3::Agents::Tools::BaseTool
  IDIOMA = ENV.fetch('OCR_IDIOMA', 'spa')
  # Evita que una imagen enorme o una descarga lenta trabe la corrida del agente.
  TIMEOUT_DESCARGA = 10

  description 'Lee el texto legible en la(s) foto(s) que el cliente acaba de enviar en la conversación ' \
              '(por ejemplo, el número de una factura, de una orden o de una cédula). Es lectura de texto ' \
              '(OCR), NO describe el producto ni daños visuales: si necesitas saber qué se ve en la foto ' \
              'más allá de texto, pídeselo al cliente con sus propias palabras.'

  def perform(tool_context)
    urls = tool_context.state[:imagenes]
    return 'El cliente no adjuntó ninguna imagen en su último mensaje.' if urls.blank?

    textos = urls.filter_map { |url| leer_texto(url).presence }
    if textos.empty?
      return 'No se encontró texto legible en la(s) imagen(es) adjunta(s); puede que la foto sea del ' \
             'producto y no tenga texto, o que la letra no sea clara. Pídele al cliente que confirme ' \
             'los datos por escrito si los necesitas.'
    end

    textos.join("\n---\n")
  rescue StandardError => e
    Rails.logger.error("[Helic3] analizar_imagen fallo: #{e.class}: #{e.message}")
    'No se pudo leer la imagen en este momento; sigue con lo que el cliente ya describió por texto.'
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
