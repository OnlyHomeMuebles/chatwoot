# frozen_string_literal: true

# FMT-04: genera un formato desde el expediente. Exige garantia, un item de esa
# garantia y una plantilla ACTIVA del formato; llena con los datos reales del
# caso, convierte a PDF con la MISMA VistaPrevia de FMT-02 (lo que se ve es lo
# que se guarda) y deja un Helic3::Documento clase 'formato' en el expediente.
# Nada se sobrescribe: cada llamada es una generacion nueva, numerada por
# (garantia, formato, item), porque la anterior puede estar firmada en papel.
class Helic3::Formatos::Generar
  # el controller la traduce a 422: el caso no esta listo para generar.
  Error = Class.new(StandardError)

  def self.call(ticket:, item:, formato:, user:)
    new(ticket, item, formato, user).call
  end

  def initialize(ticket, item, formato, user)
    @ticket = ticket
    @item = item
    @formato = formato
    @user = user
  end

  def call
    validar!
    # el PDF se arma FUERA del lock: LibreOffice es lento y no debe bloquear la
    # garantia durante la conversion.
    salida = Helic3::Formatos::VistaPrevia.call(plantilla: plantilla, item: @item, user: @user, formato: :pdf)
    # N2 (revision Jhan #116): el numero de generacion (count + 1) y el guardado van
    # DENTRO de un lock sobre la garantia (SELECT ... FOR UPDATE). Asi dos clics
    # rapidos se serializan y no repiten el numero (1, 2, ...), no dos veces 1.
    # reload limpia el display_id que el trigger deja marcado como "cambiado"
    # (load_attributes_created_by_db_triggers); si no, with_lock lo rechaza.
    garantia.reload
    garantia.with_lock do
      numero = generacion
      documento = crear_documento(salida[:bytes], numero)
      registrar_evento(documento, numero)
      documento
    end
  end

  private

  # la garantia es la del item (el item cuelga de una garantia que cuelga del
  # ticket); se valida que todo pertenezca al mismo expediente.
  def garantia
    @garantia ||= @item&.garantia
  end

  def plantilla
    @plantilla ||= @formato.plantillas.activa.first
  end

  def validar!
    raise Error, 'el item no pertenece a una garantia de este expediente' if garantia.nil? || garantia.ticket_id != @ticket.id
    raise Error, 'el formato no tiene una plantilla activa' if plantilla.nil?
  end

  # numero de generacion por garantia + formato + item: cada documento es nuevo,
  # nunca se pisa el anterior. Se cuenta sobre la instantanea en metadata.
  def generacion
    previos = @ticket.documentos.where(clase: 'formato', garantia_id: garantia.id)
                     .where("metadata ->> 'codigo_formato' = ? AND metadata ->> 'item_id' = ?",
                            @formato.codigo, @item.id.to_s)
    previos.count + 1
  end

  def crear_documento(bytes, numero)
    documento = @ticket.documentos.build(
      account: @ticket.account, garantia: garantia, clase: 'formato', origen: 'operador',
      remitente_user: @user, remitente_nombre: @user&.name, ocurrido_at: Time.current,
      titulo: titulo(numero), metadata: metadata(numero)
    )
    # el archivo se adjunta ANTES de guardar: el modelo exige exactamente una
    # procedencia (validate_una_procedencia) y sin archivo attached? fallaria.
    documento.archivo.attach(io: StringIO.new(bytes), filename: nombre_archivo(numero),
                             content_type: 'application/pdf')
    documento.save!
    documento
  end

  def titulo(numero)
    "#{@formato.nombre} · #{garantia.numero_radicado} · #{@item.producto_nombre} · generación #{numero}"
  end

  def nombre_archivo(numero)
    "formato-#{@formato.codigo}-#{garantia.numero_radicado}-#{numero}.pdf"
  end

  # metadata sostiene ante la SIC QUE se imprimio y con QUE version; los valores
  # son la instantanea exacta de lo impreso (no se recalcula al abrir el documento).
  def metadata(numero)
    {
      codigo_formato: @formato.codigo,
      plantilla_id: plantilla.id,
      plantilla_version: plantilla.version,
      item_id: @item.id,
      generacion: numero,
      valores: Helic3::Formatos::DatosDelFormato.call(item: @item, user: @user)
    }
  end

  def registrar_evento(documento, numero)
    Helic3::Evento.registrar!(
      ticket: @ticket, tipo: 'formato_generado', origen: :humano, actor: @user, garantia: garantia,
      payload: { formato: @formato.codigo, plantilla_version: plantilla.version,
                 item_id: @item.id, documento_id: documento.id, generacion: numero }
    )
  end
end
