# frozen_string_literal: true

require 'open3'
require 'timeout'

# AGT-08: lee el texto de las fotos que el cliente adjunta, con el binario local
# `tesseract`, invocado DIRECTAMENTE por Open3 (sin gema).
#
# Por que Open3 y no una gema envoltorio (rtesseract): el Gemfile es de upstream y
# la frontera del fork solo permite tocar `config/routes.rb`; agregar una gema deja
# conflictos permanentes en Gemfile.lock al sincronizar. Ademas, envolver el
# shell-out con Timeout.timeout NO mata el proceso externo: un `tesseract` colgado
# con una imagen corrupta seguiria consumiendo CPU del worker. Con Open3 tenemos el
# pid y lo matamos con SIGKILL al vencer el timeout (ver .ocr).
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
# instalado en el servidor, con el paquete del idioma que se vaya a leer. En
# produccion (Dokploy) se instala por railpack.json/nixpacks.toml (AGT-09); ver
# docs/helic3/ocr.md para desarrollo local. docker/Dockerfile es upstream y no
# lo trae -- `.disponible?` evita que una lectura fallida se confunda con "la
# foto no tenia texto" cuando en realidad el binario no esta instalado.
class Helic3::Agents::LectorDeImagenes
  IDIOMA = ENV.fetch('OCR_IDIOMA', 'spa')
  # Evita que una imagen enorme o una descarga lenta trabe el job del agente.
  TIMEOUT_DESCARGA = 10
  # tesseract corre como proceso externo: sin tope, una imagen compleja o corrupta
  # puede colgar el worker de Sidekiq indefinidamente. Al vencer, se mata el proceso.
  TIMEOUT_OCR = 15
  # AGT-09: `--list-langs` es rapido y no depende de un archivo externo (a
  # diferencia de leer una imagen real); un timeout corto alcanza.
  TIMEOUT_DISPONIBLE = 5

  # Hosts de "bucle local": Chatwoot arma la URL del adjunto con FRONTEND_URL
  # (0.0.0.0 / localhost en desarrollo Docker). Esa URL sirve para el NAVEGADOR
  # del cliente, pero este lector corre en el contenedor de Sidekiq, cuyo
  # `localhost` es él mismo y que a `0.0.0.0` no se puede conectar. Reescribimos
  # SOLO estos hosts al host interno del servicio antes de descargar.
  HOSTS_LOCALES = %w[0.0.0.0 localhost 127.0.0.1].freeze
  # Host interno alcanzable entre contenedores (nombre del servicio en Docker
  # Compose). Es inofensivo en produccion: alli FRONTEND_URL es el dominio
  # publico real, su host nunca esta en HOSTS_LOCALES y el reescrito no dispara.
  # Nota: el fetch a un host interno (IP privada) requiere que SafeFetch tenga
  # SAFE_FETCH_ALLOW_PRIVATE_NETWORK habilitado; si no, el filtro SSRF lo bloquea.
  HOST_INTERNO = ENV.fetch('OCR_HOST_INTERNO', 'rails:3000')

  def self.leer(urls)
    new.leer(urls)
  end

  # AGT-09: en Dokploy el binario se instala por railpack/nixpacks (ver
  # docker/Dockerfile, que ya NO lo trae -- es upstream). Si algun despliegue
  # se queda sin el paquete apt, cada lectura fallaria en silencio (el rescue
  # de leer_texto_seguro) y el agente le diria al cliente que la foto no tenia
  # texto legible, lo cual seria falso. Por eso se chequea antes de intentar
  # imagen por imagen.
  #
  # N1 (revision de Jhan, PR #103): solo se memoiza el `true`. El binario no
  # desaparece a mitad de la vida del worker, pero un `false` SI puede ser
  # transitorio (p. ej. un timeout de TIMEOUT_DISPONIBLE con el worker cargado
  # al arrancar) -- memoizarlo para siempre apagaria el OCR hasta el proximo
  # reinicio por un hipo puntual. Un `false` real y persistente simplemente se
  # vuelve a confirmar en cada corrida (idioma_instalado? es rapido: ENOENT
  # responde al instante, y solo paga el timeout completo si de verdad esta
  # colgado).
  def self.disponible?
    return true if @disponible

    @disponible = idioma_instalado?
  end

  # N2 (revision de Jhan, PR #111): antes solo .ocr mataba el proceso colgado con SIGKILL;
  # idioma_instalado? envolvia con Timeout.timeout, que NO mata el shell-out. Con el `false`
  # ya sin memoizar para siempre (N1), un --list-langs colgado podia dejar un huerfano por
  # CADA llamada en vez de a lo sumo uno por worker. Ahora comparten el mismo mecanismo.
  def self.idioma_instalado?
    salida = correr_con_timeout('tesseract', '--list-langs', timeout: TIMEOUT_DISPONIBLE, combinar_stderr: true)
    salida.lines.map(&:strip).include?(IDIOMA)
  rescue StandardError
    false
  end
  private_class_method :idioma_instalado?

  # Corre `tesseract <archivo> stdout -l <IDIOMA>` y devuelve el texto. La stderr de
  # tesseract (avisos de resolucion, etc.) se descarta para no ensuciar el log -- a
  # diferencia de idioma_instalado?, que SI necesita leerla (--list-langs imprime la
  # lista ahi en algunas versiones).
  def self.ocr(ruta)
    correr_con_timeout('tesseract', ruta, 'stdout', '-l', IDIOMA, timeout: TIMEOUT_OCR).strip
  end

  # Corre un binario externo con el pid vivo para poder matarlo con SIGKILL si se cuelga
  # mas del timeout (Timeout.timeout por si solo NO mata el proceso externo: un comando
  # colgado seguiria consumiendo CPU del worker). La comparten .ocr e idioma_instalado?.
  def self.correr_con_timeout(*comando, timeout:, combinar_stderr: false)
    err = combinar_stderr ? [:child, :out] : File::NULL
    Open3.popen2(*comando, err: err) do |entrada, salida, hilo|
      entrada.close
      # se lee en un hilo aparte para no bloquear si el comando llena el buffer del pipe
      lector = Thread.new { salida.read }
      if hilo.join(timeout)
        lector.value.to_s
      else
        Process.kill('KILL', hilo.pid)
        lector.kill
        raise Timeout::Error, "#{comando.first} excedio el limite de #{timeout}s"
      end
    end
  end
  private_class_method :correr_con_timeout

  # nil si no hay imagenes, o si ninguna trae texto legible; el texto unido
  # (varias imagenes, separadas) si encuentra algo. Una imagen que falla
  # (descarga, formato corrupto, timeout) NUNCA debe descartar el texto que sí
  # se pudo leer de las demás -- por eso cada una corre en su propio rescue,
  # no uno solo alrededor de todo el lote.
  def leer(urls)
    return nil if urls.blank?

    unless self.class.disponible?
      Rails.logger.error('[Helic3][ocr] tesseract no disponible')
      return nil
    end

    textos = urls.filter_map { |url| leer_texto_seguro(url) }
    textos.presence&.join("\n---\n")
  end

  private

  def leer_texto_seguro(url)
    url = reescribir_host_interno(url)
    leer_texto(url).presence
  rescue StandardError => e
    Rails.logger.error("[Helic3] lector_de_imagenes fallo con #{url}: #{e.class}: #{e.message}")
    nil
  end

  # Cambia SOLO el host cuando es de bucle local (ver HOSTS_LOCALES); una URL
  # externa (CDN de WhatsApp/Instagram) se devuelve intacta. Si la URL viene
  # mal formada, se devuelve tal cual y el fetch fallará con su rescue de siempre.
  def reescribir_host_interno(url)
    return url if HOST_INTERNO.blank?

    uri = URI.parse(url)
    return url unless HOSTS_LOCALES.include?(uri.host)

    host, sep, port = HOST_INTERNO.rpartition(':')
    if sep.empty?
      uri.host = HOST_INTERNO
    else
      uri.host = host
      uri.port = port.to_i
    end
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  # SafeFetch (ya usado en el resto del repo para URLs externas) filtra SSRF y
  # restringe el content-type a imagen; Down.download crudo no tenia ninguna
  # de las dos protecciones y la URL puede venir de un canal externo
  # (Attachment#external_url en WhatsApp/Instagram/Messenger no es un dominio
  # propio de Chatwoot).
  def leer_texto(url)
    SafeFetch.fetch(url, allowed_content_type_prefixes: ['image/'], read_timeout: TIMEOUT_DESCARGA) do |archivo|
      self.class.ocr(archivo.tempfile.path)
    end
  end
end
