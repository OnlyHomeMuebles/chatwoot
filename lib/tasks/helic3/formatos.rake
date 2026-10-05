# FMT-01 rev: chequeo de que el motor de PDF (LibreOffice) funciona en el ambiente
# (local o contenedor). Convierte una muestra .docx a .fodt y luego a PDF, imprime
# el tiempo de cada paso y termina con codigo != 0 si algo falla. Para correr
# despues de cada despliegue (igual que helic3:ocr:diagnostico de AGT-09).
#
# rubocop:disable Metrics/BlockLength -- un .rake con varias tareas tiene bloques
# largos por naturaleza; partirlo en clases solo por el conteo no aporta claridad
# (mismo criterio que Helic3::Catalogo::SeederService).
namespace :helic3 do
  namespace :formatos do
    desc 'Convierte una muestra .docx a PDF con LibreOffice (FMT-01); falla con codigo !=0 si algo sale mal'
    task diagnostico: :environment do
      bin = ENV.fetch('HELIC3_PDF_BIN', 'soffice')
      unless Helic3::Formatos::Conversor.disponible?
        warn "[helic3][formatos] LibreOffice no disponible (HELIC3_PDF_BIN=#{bin})"
        exit 1
      end

      muestra = Rails.root.join('spec/fixtures/helic3/formatos/muestra.docx')
      unless File.exist?(muestra)
        warn "[helic3][formatos] falta la muestra de prueba: #{muestra}"
        exit 1
      end
      docx = File.binread(muestra)

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      fodt = Helic3::Formatos::Conversor.a_fodt(docx)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pdf = Helic3::Formatos::Conversor.a_pdf(fodt, extension: 'fodt')
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      ruta = Rails.root.join('tmp', "formato-diagnostico-#{Time.current.to_i}.pdf")
      File.binwrite(ruta, pdf)
      puts "[helic3][formatos] OK: docx->fodt #{((t1 - t0) * 1000).round} ms, " \
           "fodt->pdf #{((t2 - t1) * 1000).round} ms, #{pdf.bytesize} bytes -> #{ruta}"
    rescue StandardError => e
      warn "[helic3][formatos] FALLO: #{e.class}: #{e.message}"
      exit 1
    end

    # FMT-01 rev (puerta de fidelidad, §4.5): convierte los 4 formatos ORIGINALES
    # de Karen y verifica que el contenido clave de cada uno sobrevive la conversion
    # (docx -> fodt -> pdf). Deja los PDF en tmp/fidelidad/ para compararlos a ojo
    # contra los exportados desde Word (ver docs/helic3/fidelidad-formatos.md). Esta
    # tarea NO corre en el dev local (no hay soffice): es para el contenedor con las
    # fuentes instaladas. Termina con codigo !=0 si algun formato falla o pierde texto.
    desc 'Convierte los 4 formatos originales y verifica que conservan su contenido (FMT-01 fidelidad)'
    task fidelidad: :environment do
      bin = ENV.fetch('HELIC3_PDF_BIN', 'soffice')
      unless Helic3::Formatos::Conversor.disponible?
        warn "[helic3][formatos] LibreOffice no disponible (HELIC3_PDF_BIN=#{bin})"
        exit 1
      end

      # tokens distintivos por formato: palabras sueltas (no frases) para que no las
      # parta el XML del .fodt. Si alguna falta, LibreOffice no leyo bien el .docx.
      formatos = [
        { archivo: 'visita-tecnica.docx',             espera: %w[DANIEL URREA MADERA CROMADO] },
        { archivo: 'recoleccion.docx',                espera: %w[Chapilla CROMADO recolectar] },
        { archivo: 'garantia-cambio-devolucion.docx', espera: %w[SOLICITUD Retracto Reversión] },
        { archivo: 'garantia-reparada.docx',          espera: %w[RADICADO Directora reparada] }
      ]

      # los originales de Karen NO viven en el repo (llevan logo de cliente y el repo
      # es PUBLICO): se bajan de Drive y se dejan en esta carpeta del contenedor.
      dir = ENV.fetch('HELIC3_FORMATOS_DIR', Rails.root.join('tmp/formatos-originales').to_s)
      base = Pathname.new(dir)
      salida = Rails.root.join('tmp/fidelidad')
      FileUtils.mkdir_p(salida)

      fallos = 0
      formatos.each do |formato|
        ruta = base.join(formato[:archivo])
        unless File.exist?(ruta)
          warn "[helic3][formatos] falta #{formato[:archivo]} en #{base} " \
               '(baja los originales de Drive; ver docs/helic3/fidelidad-formatos.md)'
          fallos += 1
          next
        end

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        fodt = Helic3::Formatos::Conversor.a_fodt(File.binread(ruta))
        pdf = Helic3::Formatos::Conversor.a_pdf(fodt, extension: 'fodt')
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        # el .fodt vuelve como bytes (ASCII-8BIT); es UTF-8 de verdad, asi que se
        # reinterpreta antes de buscar (si no, include? de un token acentuado revienta).
        # tags fuera (con espacio para no pegar palabras de runs distintos) y se busca cada token.
        texto = fodt.to_s.dup.force_encoding('UTF-8').gsub(/<[^>]+>/, ' ')
        faltan = formato[:espera].reject { |token| texto.include?(token) }

        destino = salida.join(formato[:archivo].sub(/\.docx\z/, '.pdf'))
        File.binwrite(destino, pdf)

        if faltan.empty?
          puts "[helic3][formatos] OK #{formato[:archivo]}: #{pdf.bytesize} bytes, #{ms} ms -> #{destino}"
        else
          warn "[helic3][formatos] CONTENIDO FALTANTE en #{formato[:archivo]}: #{faltan.join(', ')}"
          fallos += 1
        end
      rescue StandardError => e
        warn "[helic3][formatos] FALLO en #{formato[:archivo]}: #{e.class}: #{e.message}"
        fallos += 1
      end

      if fallos.positive?
        warn "[helic3][formatos] fidelidad: #{fallos} formato(s) con problemas"
        exit 1
      end
      puts "[helic3][formatos] fidelidad: los #{formatos.size} formatos se convirtieron y conservan su contenido clave"
      puts "[helic3][formatos] ahora compara a ojo los PDF de #{salida} contra los exportados desde Word " \
           '(checklist en docs/helic3/fidelidad-formatos.md)'
    end
  end
end
# rubocop:enable Metrics/BlockLength
