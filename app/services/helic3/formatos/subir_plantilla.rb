# frozen_string_literal: true

# FMT-02: valida un .docx subido, lo convierte a .fodt, verifica sus marcadores contra
# el diccionario y crea la plantilla en 'borrador' con la version siguiente. Devuelve un
# Resultado que el controlador traduce a 201 o 422.
class Helic3::Formatos::SubirPlantilla
  # :exito (no :ok?): un miembro de Struct no puede terminar en '?'. El metodo ok? lo expone.
  Resultado = Struct.new(:exito, :plantilla, :errores, :advertencias, keyword_init: true) do
    def ok? = exito
  end

  FIRMA_DOCX = "PK\x03\x04".b
  TIPO_DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'

  def self.call(formato:, archivo:, user:)
    new(formato, archivo, user).call
  end

  def initialize(formato, archivo, user)
    @formato = formato
    @archivo = archivo
    @user = user
  end

  def call
    error = validar_archivo
    return fallo([error]) if error

    bytes = @archivo.read
    fodt = Helic3::Formatos::Conversor.a_fodt(bytes)
    marcadores = Helic3::Formatos::LlenarPlantilla.marcadores_de(fodt)
    desconocidos = marcadores.reject { |marcador| Helic3::Formatos::Marcadores.conocido?(marcador) }
    return fallo(mensajes_desconocidos(desconocidos)) if desconocidos.any?

    crear(bytes, fodt, marcadores)
  rescue Helic3::Formatos::Conversor::Error
    fallo(['no se pudo leer el archivo'])
  end

  private

  # extension .docx Y cabecera de bytes PK (un .docx es un zip) + tope de tamano.
  def validar_archivo
    return 'solo se aceptan archivos .docx' unless @archivo.original_filename.to_s.downcase.end_with?('.docx')
    return 'el archivo no es un .docx válido' unless cabecera_docx?
    return "el archivo supera #{max_mb} MB" if @archivo.size.to_i > max_mb * 1_000_000

    nil
  end

  def cabecera_docx?
    cabecera = @archivo.read(4)
    @archivo.rewind
    cabecera == FIRMA_DOCX
  end

  def max_mb
    ENV.fetch('HELIC3_PLANTILLA_MAX_MB', '10').to_i
  end

  def crear(bytes, fodt, marcadores)
    plantilla = @formato.plantillas.new(
      account: @formato.account, version: siguiente_version, estado: 'borrador',
      marcadores: marcadores, subido_por_id: @user&.id, subido_por_nombre: @user&.name
    )
    plantilla.original.attach(io: StringIO.new(bytes), filename: @archivo.original_filename, content_type: TIPO_DOCX)
    plantilla.fodt.attach(io: StringIO.new(fodt), filename: 'plantilla.fodt', content_type: 'text/xml')
    plantilla.save!
    Resultado.new(exito: true, plantilla: plantilla, errores: [],
                  advertencias: marcadores.empty? ? ['la plantilla no tiene marcadores'] : [])
  end

  def siguiente_version
    (@formato.plantillas.maximum(:version) || 0) + 1
  end

  # sugiere el marcador mas cercano con DidYouMean (libreria estandar).
  def mensajes_desconocidos(desconocidos)
    corrector = DidYouMean::SpellChecker.new(dictionary: Helic3::Formatos::Marcadores.nombres)
    desconocidos.map do |marcador|
      sugerencia = corrector.correct(marcador).first
      sugerencia ? "{{#{marcador}}} no existe; ¿quisiste decir {{#{sugerencia}}}?" : "{{#{marcador}}} no existe"
    end
  end

  def fallo(errores)
    Resultado.new(exito: false, plantilla: nil, errores: errores, advertencias: [])
  end
end
