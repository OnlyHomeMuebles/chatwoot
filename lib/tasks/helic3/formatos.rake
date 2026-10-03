# FMT-01 rev: chequeo de que el motor de PDF (LibreOffice) funciona en el ambiente
# (local o contenedor). Convierte una muestra .docx a .fodt y luego a PDF, imprime
# el tiempo de cada paso y termina con codigo != 0 si algo falla. Para correr
# despues de cada despliegue (igual que helic3:ocr:diagnostico de AGT-09).
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
  end
end
