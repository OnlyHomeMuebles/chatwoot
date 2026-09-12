# frozen_string_literal: true

# GAR-02: crea el radicado de garantia cuando una PQR se resuelve con un
# resultado que la abre. Lo llama Helic3::Casos::Resolver desde su gancho, dentro
# de la misma transaccion (si la garantia falla, la resolucion se revierte).
#
# La DECISION de abrir ya la tomo el resultado (Resolver evalua abre_garantia?);
# aqui no se vuelve a preguntar: se ejecuta la apertura. El primer proceso del
# item sale de la cobertura de la ciudad (catalogo), no de un if.
class Helic3::Casos::AbrirGarantia
  # contradiccion del catalogo: el resultado abre garantia pero el motivo del
  # expediente dice que NUNCA la abre. Error ruidoso, no apertura silenciosa.
  class MotivoNoAbreGarantia < StandardError; end

  def initialize(ticket:, cobertura_ciudad:, items:)
    @ticket = ticket
    @cobertura_ciudad = cobertura_ciudad
    @items = items
  end

  def call
    # idempotencia: un expediente tiene UNA garantia. Doble clic o reintento no
    # crea una segunda.
    return @ticket.garantia if @ticket.garantia.present?

    validar_cobertura!
    validar_motivo_coherente!

    garantia = Helic3::Garantia.create!(
      account: @ticket.account,
      ticket: @ticket,
      cobertura_ciudad: @cobertura_ciudad
    )
    @items.each { |datos| crear_item(garantia, datos) }
    garantia
  end

  private

  # sin ciudad de cobertura no hay a donde enrutar la garantia: se rechaza con un
  # mensaje claro (ArgumentError -> 422 en el controlador) en vez de crear un
  # radicado roto sin ciudad ni proceso, en silencio. Es el fallo que tuvo AGT-03
  # en su primera version y que ahora tampoco puede colarse desde el panel.
  def validar_cobertura!
    return if @cobertura_ciudad.present?

    raise ArgumentError, 'la garantia requiere una ciudad de cobertura'
  end

  # el motivo del expediente (MotivoPqr) tiene el enum abre_garantia; si es
  # 'nunca' y el resultado igual abrio garantia, el catalogo se contradice.
  def validar_motivo_coherente!
    motivo = @ticket.motivo_pqr
    return unless motivo&.abre_garantia_nunca?

    raise MotivoNoAbreGarantia,
          "el motivo '#{motivo.codigo}' tiene abre_garantia: nunca, pero el resultado abre garantia"
  end

  def crear_item(garantia, datos)
    garantia.items.create!(
      account: @ticket.account,
      producto_nombre: datos[:producto_nombre],
      producto_referencia: datos[:producto_referencia],
      motivo_garantia: datos[:motivo_garantia],
      detalle_tipificado: datos[:detalle_tipificado],
      proceso: proceso_inicial
    )
  end

  # El primer proceso sale de la cobertura de la ciudad, no de un if. origen_ruta
  # es un codigo del catalogo de procesos: con tecnico -> visita tecnica; sin
  # tecnico -> recoleccion. Si la ciudad no trae origen_ruta, el item nace SIN
  # proceso (el estado "mas atrasado" que proceso_visible ya sabe leer).
  def proceso_inicial
    codigo = @cobertura_ciudad&.origen_ruta
    return if codigo.blank?

    Helic3::Catalogo::ProcesoGarantia.find_by(account: @ticket.account, codigo: codigo)
  end
end
