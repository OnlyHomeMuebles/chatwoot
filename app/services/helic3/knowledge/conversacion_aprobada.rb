# frozen_string_literal: true

# AGT-05: convierte UNA conversacion marcada como bien resuelta en material de voz
# para el RAG. Arma la transcripcion por turnos (Cliente / Asesor), la anonimiza y
# la persiste como Document dataset idempotente (nombre `conversacion_<display_id>`).
#
# La etiqueta de Chatwoot `voz_aprobada` es la UNICA puerta: sin ella no se ingesta
# nada. Es el riesgo que el ticket exige evitar: si el agente aprendiera de cualquier
# conversacion resuelta, aprenderia de sus propios errores no revisados y el tono se
# degradaria solo. Solo cuentan las conversaciones que una persona aprobo.
class Helic3::Knowledge::ConversacionAprobada
  ETIQUETA_APROBACION = 'voz_aprobada'

  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
  end

  # @return [Symbol] :no_aprobada, :sin_contenido, o el resultado de la ingestion
  #   (:ingested / :unchanged). Un fallo de embedding se propaga (no en silencio):
  #   el Document queda en `failed` con el error en metadata.
  def call
    return :no_aprobada unless aprobada?

    dialogo = transcripcion
    return :sin_contenido if dialogo.blank?

    document = Helic3::Knowledge::Document.find_or_initialize_by(
      account: @account, name: nombre_documento, source_type: :dataset
    )
    document.content = dialogo
    document.save!

    Helic3::Knowledge::IngestionService.new(document).perform
  end

  private

  def aprobada?
    @conversation.label_list.include?(ETIQUETA_APROBACION)
  end

  def nombre_documento
    "conversacion_#{@conversation.display_id}"
  end

  # Dialogo real por turnos, anonimizado. Solo mensajes reales del hilo (entrantes
  # del cliente y salientes del asesor), sin notas privadas ni mensajes vacios.
  def transcripcion
    turnos = @conversation.messages
                          .where(message_type: %i[incoming outgoing], private: false)
                          .where.not(content: [nil, ''])
                          .order(created_at: :asc)
                          .map { |mensaje| "#{etiqueta(mensaje)}: #{mensaje.content}" }
                          .join("\n")

    Helic3::Knowledge::Anonimizador.call(turnos)
  end

  def etiqueta(mensaje)
    mensaje.incoming? ? 'Cliente' : 'Asesor'
  end
end
