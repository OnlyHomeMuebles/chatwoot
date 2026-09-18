# frozen_string_literal: true

# AGT-06: la compuerta determinista de radicacion corre en SU PROPIO job, por fuera del
# job que le responde al cliente. Asi la clasificacion (una llamada LLM) no retrasa la
# respuesta ni deja al cliente viendo "escribiendo…", y un fallo aqui nunca afecta lo que
# ya recibio. Lo encola ProcessConversationJob solo cuando el caso puede necesitar
# expediente. Es idempotente: si no amerita o ya hay expediente vigente, no crea nada.
class Helic3::RadicarAutomaticoJob < ApplicationJob
  queue_as :low

  # Seguimiento al cliente cuando la compuerta radica en modo autónomo (Karen, 18-ago).
  SEGUIMIENTO_CLIENTE = 'Tu caso quedó registrado con el número %<numero>s. Te iremos contando por aquí cómo avanza 💙.'

  def perform(account_id:, conversation_id:)
    account = Account.find_by(id: account_id)
    conversation = account&.conversations&.find_by(display_id: conversation_id)
    return if conversation.nil?

    ticket = Helic3::Casos::RadicacionAutomatica.new(account: account, conversation: conversation).call
    return unless ticket.is_a?(Helic3::Ticket)

    client = Helic3::ChatwootClient.new(account_id: account_id)
    nota_radicacion_automatica(client, conversation_id, ticket)
    avisar_radicado_al_cliente(client, conversation_id, account, ticket)
  rescue StandardError => e
    Rails.logger.error("[Helic3] radicacion automatica conv=#{conversation_id}: #{e.class}: #{e.message}")
  end

  private

  # Deja la MISMA nota privada al operador que dejaria la tool: asi la traza "dorada"
  # aparece sin importar quien radico. Best-effort (queda el warn si falla).
  def nota_radicacion_automatica(client, display_id, ticket)
    client.create_message(display_id, content: nota_de(ticket), private_note: true)
  rescue StandardError => e
    Rails.logger.warn("[Helic3] no se pudo dejar la nota de radicacion conv=#{display_id}: #{e.message}")
  end

  def nota_de(ticket)
    numero = ticket.numero_radicado || ticket.ticket_number
    vence = ticket.plazo_respuesta_vence_at&.to_date || 'sin plazo (no genera radicado)'
    "Radicacion automatica del agente — expediente #{numero}: " \
      "tipo #{ticket.tipo&.nombre}, motivo #{ticket.motivo_pqr&.nombre} " \
      "(categoria #{ticket.categoria&.nombre}). Vence: #{vence}."
  end

  # Karen (18-ago) pidio que el cliente quede con un ticket de seguimiento. Solo en modo
  # autonomo (autonomia_radicar_pqr = ejecuta) y con numero de radicado; en modo propone no
  # se le adelanta nada al cliente.
  def avisar_radicado_al_cliente(client, display_id, account, ticket)
    return if ticket.numero_radicado.blank?
    return unless autonomia_ejecuta?(account)

    client.create_message(display_id, content: format(SEGUIMIENTO_CLIENTE, numero: ticket.numero_radicado),
                                      message_type: 'outgoing')
  rescue StandardError => e
    Rails.logger.warn("[Helic3] no se pudo avisar el radicado al cliente conv=#{display_id}: #{e.message}")
  end

  def autonomia_ejecuta?(account)
    Helic3::Catalogo::Parametro
      .find_by(account_id: account.id, clave: Helic3::Agents::Tools::RadicarPqrTool::PARAMETRO_AUTONOMIA)
      &.valor == 'ejecuta'
  end
end
