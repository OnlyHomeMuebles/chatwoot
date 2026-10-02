# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# FMT-01: convierte HTML en un PDF A4 con un navegador headless (Chromium),
# invocado por Open3 — el MISMO patron que Helic3::Agents::LectorDeImagenes.ocr.
#
# Por que un binario y no una gema: el Gemfile es de upstream y la frontera del
# fork solo permite tocar config/routes.rb; no entra prawn, wicked_pdf ni grover.
# HTML + CSS de impresion da la fidelidad que piden los formatos (tablas con
# bordes, casillas, firmas) y cualquiera del equipo mantiene las plantillas.
#
# Robustez (igual que el OCR): argumentos en arreglo (nunca por shell, no hay
# inyeccion), se MATA el proceso con SIGKILL si vence el timeout (Timeout.timeout
# no mata un shell-out), y el directorio temporal se limpia SIEMPRE (Dir.mktmpdir
# con bloque). Nunca devuelve un PDF vacio: verifica el codigo de salida y que el
# archivo empiece con %PDF, o levanta RenderizadorPdf::Error.
#
# Binario y timeout por ENV (infraestructura, no negocio):
#   HELIC3_PDF_BIN (default 'chromium'), HELIC3_PDF_TIMEOUT (segundos, default 20).
class Helic3::Formatos::RenderizadorPdf
  class Error < StandardError; end

  BIN = ENV.fetch('HELIC3_PDF_BIN', 'chromium')
  TIMEOUT = ENV.fetch('HELIC3_PDF_TIMEOUT', '20').to_i
  # tope del chequeo de version. Holgado a proposito: el PRIMER lanzamiento de
  # chromium en frio (enlazado dinamico, carga de .so) puede tardar varios
  # segundos en un contenedor lento, y un tope corto haria que disponible? diera
  # un falso negativo ("motor no disponible") aunque el binario si sirva.
  TIMEOUT_VERSION = 15

  def self.call(html)
    new.call(html)
  end

  # ¿esta el binario en el sistema? Se memoiza por proceso (como AGT-09): en
  # produccion no cambia mientras el contenedor vive.
  def self.disponible?
    return @disponible unless @disponible.nil?

    @disponible = new.disponible?
  end

  # bytes del PDF, o levanta Error. El HTML se escribe en un tmpdir propio que se
  # borra al salir del bloque, pase lo que pase.
  def call(html)
    Dir.mktmpdir('helic3-pdf') do |dir|
      entrada = File.join(dir, 'formato.html')
      salida = File.join(dir, 'formato.pdf')
      File.write(entrada, html)
      ejecutar(comando(dir, entrada, salida))
      leer_pdf(salida)
    end
  end

  def disponible?
    ejecutar([BIN, '--version'], timeout: TIMEOUT_VERSION)
    true
  rescue StandardError
    false
  end

  private

  # Argumentos exactos del ticket. --user-data-dir aislado en el tmpdir para no
  # tocar el perfil del sistema; --no-pdf-header-footer para que no imprima la URL
  # ni la fecha del navegador (esos van en la plantilla).
  def comando(dir, entrada, salida)
    [BIN, '--headless', '--no-sandbox', '--disable-gpu',
     "--user-data-dir=#{dir}", '--no-pdf-header-footer',
     "--print-to-pdf=#{salida}", "file://#{entrada}"]
  end

  # Corre el binario y espera con timeout; si se pasa, mata TODO el grupo y revienta.
  # La salida (stdout+stderr fusionados) se drena en un hilo para no bloquear el
  # pipe, y se descarta: el navegador es ruidoso y nada de eso es el PDF.
  #
  # pgroup: true hace al proceso lider de su propio grupo; Process.kill con pid
  # NEGATIVO manda la señal a todo el grupo. Necesario porque chromium levanta
  # hijos (zygote, renderer): matar solo al padre los dejaria huerfanos escribiendo
  # en el --user-data-dir, y esa basura podria tumbar la limpieza del mktmpdir.
  def ejecutar(args, timeout: TIMEOUT)
    Open3.popen2e(*args, pgroup: true) do |entrada, salida, hilo|
      entrada.close
      drenaje = Thread.new { salida.read }
      if hilo.join(timeout)
        drenaje.join
        estado = hilo.value
        raise Error, "chromium salió con código #{estado.exitstatus}" unless estado.success?
      else
        Process.kill('KILL', -hilo.pid)
        drenaje.kill
        raise Error, "chromium excedió el límite de #{timeout}s"
      end
    end
  end

  def leer_pdf(salida)
    raise Error, 'chromium no generó el PDF' unless File.exist?(salida)

    bytes = File.binread(salida)
    raise Error, 'la salida no empieza con %PDF' unless bytes.start_with?('%PDF')

    bytes
  end
end
