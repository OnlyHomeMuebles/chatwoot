# FMT-01: chequeo de que el motor de PDF funciona en el ambiente (local o
# contenedor). Renderiza una pagina de prueba con el layout de impresion y la
# convierte a PDF; termina con codigo != 0 si algo falla, para usarlo despues de
# cada despliegue (igual que helic3:ocr:diagnostico de AGT-09).
namespace :helic3 do
  namespace :formatos do
    desc 'Renderiza una pagina de prueba a PDF con el motor (FMT-01); falla con codigo !=0 si algo sale mal'
    task diagnostico: :environment do
      bin = ENV.fetch('HELIC3_PDF_BIN', 'chromium')
      unless Helic3::Formatos::RenderizadorPdf.disponible?
        warn "[helic3][formatos] binario de PDF no disponible (HELIC3_PDF_BIN=#{bin})"
        exit 1
      end

      html = ActionController::Base.render(
        template: 'helic3/formatos/diagnostico',
        layout: 'helic3/formato',
        assigns: { fecha: Time.current.in_time_zone('America/Bogota').strftime('%Y-%m-%d %H:%M') }
      )

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pdf = Helic3::Formatos::RenderizadorPdf.call(html)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round

      ruta = Rails.root.join('tmp', "formato-diagnostico-#{Time.current.to_i}.pdf")
      File.binwrite(ruta, pdf)
      puts "[helic3][formatos] OK: #{pdf.bytesize} bytes en #{ms} ms -> #{ruta}"
    rescue StandardError => e
      warn "[helic3][formatos] FALLO: #{e.class}: #{e.message}"
      exit 1
    end
  end
end
