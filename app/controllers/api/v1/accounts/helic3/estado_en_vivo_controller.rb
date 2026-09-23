class Api::V1::Accounts::Helic3::EstadoEnVivoController < Api::V1::Accounts::BaseController
  # H3A-15: estado en vivo por conversación. Solo administrador.
  before_action :check_admin_authorization?

  # Conversaciones que la IA está atendiendo ahora: tienen un agente activo emitido
  # por el job (helic3_agente_activo) y NO fueron pausadas por intervención humana.
  def index
    @conversaciones = Current.account.conversations
                             .where("custom_attributes->>'helic3_agente_activo' IS NOT NULL")
                             .where("COALESCE(custom_attributes->>'helic3_ia_pausada', 'false') NOT IN ('true', '1')")
                             .order(updated_at: :desc).limit(100)
    @nombres_agentes = Helic3::Agente.where(account: Current.account).pluck(:codigo, :nombre).to_h
  end

  # crit 2: intervenir = pausar la IA en esa conversación (un humano toma el relevo).
  # Escribir el custom_attribute dispara conversation.updated, así el estado se refleja
  # en vivo. El job respeta helic3_ia_pausada y deja de responder.
  def intervenir
    conversacion = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    conversacion.update!(
      custom_attributes: conversacion.custom_attributes.merge('helic3_ia_pausada' => true)
    )
    head :ok
  end
end
