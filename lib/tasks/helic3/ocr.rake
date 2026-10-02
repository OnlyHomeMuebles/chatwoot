# frozen_string_literal: true

namespace :helic3 do
  namespace :ocr do
    desc 'AGT-09: diagnostico de OCR en el servidor -- version, idiomas instalados y ' \
         'lectura de una imagen de muestra. Termina con codigo distinto de 0 si algo falla.'
    task diagnostico: :environment do
      require 'open3'

      version, = Open3.capture2e('tesseract', '--version')
      puts "version: #{version.lines.first&.strip}"

      idiomas, = Open3.capture2e('tesseract', '--list-langs')
      puts idiomas

      unless Helic3::Agents::LectorDeImagenes.disponible?
        warn '[Helic3][ocr] tesseract no disponible o falta el idioma ' \
             "#{Helic3::Agents::LectorDeImagenes::IDIOMA}"
        exit 1
      end

      muestra = Rails.root.join('spec/fixtures/helic3/ocr_muestra.png')
      texto = Helic3::Agents::LectorDeImagenes.ocr(muestra.to_s)
      puts "texto leido de la muestra: #{texto.inspect}"

      if texto.blank?
        warn '[Helic3][ocr] la imagen de muestra no produjo texto'
        exit 1
      end
    rescue StandardError => e
      warn "[Helic3][ocr] diagnostico fallo: #{e.class}: #{e.message}"
      exit 1
    end
  end
end
