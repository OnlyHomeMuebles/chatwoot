class Api::V1::Accounts::Helic3::EstadoEnVivoController < Api::V1::Accounts::BaseController
  # H3A-15: estado en vivo por conversación. Solo administrador.
  before_action :check_admin_authorization?

  # Conversaciones que la IA está atendiendo ahora: en territorio del bot (status pending),
  # con un agente activo emitido por el job (helic3_agente_activo). El filtro por 'pending'
  # (B2) evita mostrar como "IA atendiendo" casos ya resueltos o derivados a un humano; una
  # conversación intervenida pasa a 'open' y sale sola de la lista. includes(:contact) evita
  # el N+1 del jbuilder (B2/N1).
  def index
    @conversaciones = Current.account.conversations
                             .where(status: :pending)
                             .where("custom_attributes->>'helic3_agente_activo' IS NOT NULL")
                             .includes(:contact)
                             .order(updated_at: :desc).limit(100)
    @nombres_agentes = Helic3::Agente.where(account: Current.account).pluck(:codigo, :nombre).to_h
  end

  # crit 2: intervenir = un humano toma el relevo. Se saca la conversación del territorio del
  # bot (status 'open') y se asigna al asesor: el webhook ignora todo lo que no está en
  # 'pending', así el bot deja de responder SIN depender de una bandera, y la conversación
  # aparece en la bandeja del asesor. La bandera helic3_ia_pausada se conserva por auditoría
  # y como guarda de la corrida en vuelo (el job la respeta si ya venía corriendo). Escribir
  # el custom_attribute dispara conversation.updated, así el estado se refleja en vivo (B3).
  def intervenir
    conversacion = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    conversacion.update!(
      custom_attributes: conversacion.custom_attributes.merge('helic3_ia_pausada' => true),
      status: :open,
      assignee: Current.user
    )
    head :ok
  end
end
