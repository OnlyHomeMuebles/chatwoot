# frozen_string_literal: true

# FMT-02: llena el .fodt de la plantilla (con datos de ejemplo o de un item real) y lo
# convierte a PDF o a Word segun `formato`. Es la MISMA funcion que usa FMT-04 para
# generar: lo que se ve en la vista previa es lo que se guarda.
class Helic3::Formatos::VistaPrevia
  SALIDAS = {
    pdf: { mime: 'application/pdf', ext: 'pdf' },
    docx: { mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', ext: 'docx' }
  }.freeze

  def self.call(plantilla:, item: nil, user: nil, formato: :pdf)
    salida = SALIDAS.fetch(formato.to_sym) { raise ArgumentError, "formato no soportado: #{formato}" }
    valores = valores_para(item, user)
    lleno = Helic3::Formatos::LlenarPlantilla.call(plantilla.fodt.download, valores)
    { bytes: convertir(lleno, formato.to_sym), tipo_mime: salida[:mime], extension: salida[:ext] }
  end

  def self.valores_para(item, user)
    if item
      Helic3::Formatos::DatosDelFormato.call(item: item, user: user)
    else
      Helic3::Formatos::DatosDelFormato::DATOS_DE_EJEMPLO
    end
  end

  def self.convertir(fodt, formato)
    if formato == :docx
      Helic3::Formatos::Conversor.a_docx(fodt, extension: 'fodt')
    else
      Helic3::Formatos::Conversor.a_pdf(fodt, extension: 'fodt')
    end
  end
end
