# frozen_string_literal: true

# AGT-07: registra que el cliente AUTORIZO el tratamiento de sus datos personales. El sello
# queda en un atributo de la CONVERSACION (no en la memoria del modelo), para que la
# idempotencia del aviso sobreviva entre corridas, y deja una nota privada con la fecha y el
# texto exacto del aviso vigente (trazabilidad para auditoria). No agrega columnas upstream.
class Helic3::Agents::Tools::RegistrarConsentimientoTool < Helic3::Agents::Tools::BaseTool
  ATRIBUTO_CONSENTIMIENTO = 'helic3_consentimiento_datos_at'
  PARAM_AVISO = 'aviso_datos_personales'

  description 'Registra que el cliente AUTORIZO el tratamiento de sus datos personales. Usala UNA sola ' \
              'vez, cuando el cliente acepte en lenguaje natural (si, claro, dale, ok) el aviso de datos. ' \
              'NO la uses si el cliente no autoriza.'

  def perform(tool_context)
    sello = Time.current.iso8601
    with_api_error_handling do
      cid = conversation_id(tool_context)
      client(tool_context).update_custom_attributes(cid, { ATRIBUTO_CONSENTIMIENTO => sello })
      dejar_nota(tool_context, cid, sello)
      'Consentimiento de datos registrado. Continua atendiendo al cliente con normalidad y NO vuelvas ' \
        'a mostrar el aviso de datos en esta conversacion.'
    end
  end

  private

  def dejar_nota(tool_context, cid, sello)
    nota = "Consentimiento de tratamiento de datos AUTORIZADO por el cliente el #{sello}. " \
           "Aviso vigente presentado: \"#{aviso_vigente(tool_context)}\""
    client(tool_context).create_message(cid, content: nota, message_type: 'activity')
  end

  # el texto exacto del aviso sale del catalogo (AGT-07: nunca del prompt ni del codigo)
  def aviso_vigente(tool_context)
    account_id = tool_context.context[:account_id]
    Helic3::Catalogo::Parametro.find_by(account_id: account_id, clave: PARAM_AVISO)&.valor ||
      '(aviso de datos no configurado en el catalogo)'
  end
end
