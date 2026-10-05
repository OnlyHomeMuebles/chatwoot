# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# FMT-01 rev: convierte un .docx (o su .fodt ya relleno) en PDF A4 con LibreOffice
# headless (soffice), invocado por Open3 — el MISMO patron de robustez que
# Helic3::Agents::LectorDeImagenes.ocr.
#
# Por que LibreOffice: las plantillas ahora son los .docx de Karen, y hace falta
# un motor que abra .docx respetando fuentes, tablas y estilos de Word. Por que un
# binario y no una gema: el Gemfile es de upstream y la frontera del fork no
# permite agregar gemas de .docx (rubyzip, docx, sablon, caracal). LibreOffice
# ademas da el .fodt (OpenDocument plano: un solo XML) que FMT-02 rellena con
# Nokogiri.
#
# Robustez (igual que antes): argumentos en arreglo (nunca por shell, sin
# inyeccion), SIGKILL a TODO el grupo si vence el timeout (Timeout.timeout no mata
# un shell-out), tmpdir que se limpia SIEMPRE (Dir.mktmpdir con bloque), y nunca
# devuelve un PDF vacio: verifica el codigo de salida y que empiece con %PDF, o
# levanta Conversor::Error.
#
# Perfil por conversion: cada corrida usa su propio -env:UserInstallation dentro
# del tmpdir. Sin eso, dos conversiones a la vez se bloquean por el lock del
# perfil global de LibreOffice.
#
# Binario y timeout por ENV (infraestructura, no negocio):
#   HELIC3_PDF_BIN (default 'soffice'), HELIC3_PDF_TIMEOUT (segundos, default 30:
#   el primer arranque en frio de LibreOffice es lento).
class Helic3::Formatos::Conversor
  class Error < StandardError; end

  BIN = ENV.fetch('HELIC3_PDF_BIN', 'soffice')
  TIMEOUT = ENV.fetch('HELIC3_PDF_TIMEOUT', '30').to_i
  # tope del chequeo de version. Holgado a proposito: el primer arranque de
  # soffice en frio puede tardar varios segundos en un contenedor lento.
  TIMEOUT_VERSION = 20
  EXT_ENTRADA = %w[docx fodt].freeze

  # XML del documento como .fodt. Lo usa Helic3::Formatos::LlenarPlantilla (FMT-02).
  def self.a_fodt(docx_bytes)
    new.convertir(docx_bytes, extension: 'docx', destino: 'fodt')
  end

  # bytes del PDF a partir de un .docx o de un .fodt ya relleno.
  def self.a_pdf(bytes, extension:)
    new.convertir(bytes, extension: extension, destino: 'pdf')
  end

  # ¿esta el binario en el sistema? Memoizado por proceso (como AGT-09).
  def self.disponible?
    return @disponible unless @disponible.nil?

    @disponible = new.disponible?
  end

  # Convierte `bytes` (de tipo `extension`) al formato `a` y devuelve sus bytes.
  # tmpdir propio que se borra al salir del bloque, pase lo que pase.
  def convertir(bytes, extension:, destino:)
    raise Error, "extension de entrada no soportada: #{extension}" unless EXT_ENTRADA.include?(extension.to_s)

    Dir.mktmpdir('helic3-conversor') do |dir|
      entrada = File.join(dir, "entrada.#{extension}")
      File.binwrite(entrada, bytes)
      ejecutar(comando(dir, entrada, destino))
      leer_salida(File.join(dir, "entrada.#{destino}"), destino)
    end
  end

  def disponible?
    ejecutar([BIN, '--version'], timeout: TIMEOUT_VERSION)
    true
  rescue StandardError
    false
  end

  private

  # --headless/--norestore/--nolockcheck/--nodefault: sin UI, sin recuperar
  # sesiones, sin chequeo de lock, sin documento en blanco. -env:UserInstallation
  # propio aisla el perfil (clave para la concurrencia). --convert-to deja el
  # resultado en --outdir con el mismo nombre base y la extension nueva.
  def comando(dir, entrada, destino)
    perfil = "file://#{File.join(dir, 'perfil')}"
    [BIN, '--headless', '--norestore', '--nolockcheck', '--nodefault',
     "-env:UserInstallation=#{perfil}",
     '--convert-to', destino, '--outdir', dir, entrada]
  end

  # Corre el binario y espera con timeout; si se pasa, mata TODO el grupo y revienta.
  # La salida (stdout+stderr) se drena en un hilo para no bloquear el pipe y se
  # descarta. pgroup: true + pid NEGATIVO mata al grupo entero: soffice levanta
  # procesos hijos y matar solo al padre los dejaria huerfanos.
  def ejecutar(args, timeout: TIMEOUT)
    Open3.popen2e(*args, pgroup: true) do |entrada, salida, hilo|
      entrada.close
      drenaje = Thread.new { salida.read }
      if hilo.join(timeout)
        drenaje.join
        estado = hilo.value
        raise Error, "soffice salió con código #{estado.exitstatus}" unless estado.success?
      else
        Process.kill('KILL', -hilo.pid)
        drenaje.kill
        raise Error, "soffice excedió el límite de #{timeout}s"
      end
    end
  end

  def leer_salida(ruta, destino)
    raise Error, "soffice no generó la salida .#{destino}" unless File.exist?(ruta)

    bytes = File.binread(ruta)
    raise Error, 'el PDF no empieza con %PDF' if destino == 'pdf' && !bytes.start_with?('%PDF')

    bytes
  end
end
