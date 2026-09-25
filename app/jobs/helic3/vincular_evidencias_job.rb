# frozen_string_literal: true

# EVI-02: dispara la vinculacion de evidencias en el ciclo de mensaje entrante,
# desacoplada del pipeline del agente (ProcessConversationJob) -- corre incluso
# cuando el mensaje no trae texto y por tanto no se invoca al modelo de
# lenguaje. Si el expediente todavia no existe (el cliente casi siempre manda
# la foto antes de que exista el radicado), no hay nada que hacer aqui: el
# barrido hacia atras de Helic3::Casos::Radicar las recoge en cuanto nace.
class Helic3::VincularEvidenciasJob < ApplicationJob
  queue_as :low

  def perform(account_id:, conversation_id:)
    account = Account.find_by(id: account_id)
    conversation = account&.conversations&.find_by(display_id: conversation_id)
    ticket = conversation && Helic3::Ticket.where(account: account, conversation: conversation)
                                           .order(created_at: :desc).first
    return if ticket.nil?

    Helic3::Casos::VincularEvidencias.call(ticket)
  rescue StandardError => e
    Rails.logger.error("[Helic3] vincular_evidencias conv=#{conversation_id}: #{e.class}: #{e.message}")
  end
end
