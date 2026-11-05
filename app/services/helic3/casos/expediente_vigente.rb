# frozen_string_literal: true

# ERP-06/T2: unica regla de idempotencia contra el doble expediente. Antes
# RadicarPqrTool (la herramienta del agente) y RadicacionAutomatica#expediente_existente?
# (la compuerta) tenian cada una su propio criterio -- la primera con ventana,
# la segunda sin ella -- y por eso se seguian duplicando expedientes cuando las
# dos corrian sobre el mismo hilo.
#
# Regla unica: bloquea un expediente VIGENTE (respondida_at IS NULL) o uno que
# se acaba de responder dentro de la ventana (cubre el ciclo radica -> resuelve
# -> vuelve a radicar observado en vivo). Pasada la ventana, una PQR respondida
# ya no bloquea: un caso NUEVO en el mismo hilo vuelve a ser radicable.
class Helic3::Casos::ExpedienteVigente
  PARAMETRO_VENTANA = 'ventana_doble_radicacion_minutos'
  # Si la cuenta no tiene el parametro sembrado (aun no corrio la migracion de
  # siembra), nada debe fallar antes de tiempo: se usa este valor por defecto.
  VENTANA_POR_DEFECTO_MINUTOS = 10

  def self.para(account:, conversation_id:)
    new(account: account, conversation_id: conversation_id).call
  end

  def initialize(account:, conversation_id:)
    @account = account
    @conversation_id = conversation_id
  end

  # @return [Helic3::Ticket, nil] el expediente que bloquea una nueva
  #   radicacion, o nil si no hay ninguno. Si hay varios, el mas antiguo.
  def call
    return nil if @conversation_id.blank?

    @account.tickets
            .where(conversation_id: @conversation_id)
            .where('respondida_at IS NULL OR respondida_at > ?', ventana.ago)
            .order(created_at: :asc)
            .first
  end

  private

  def ventana
    valor = Helic3::Catalogo::Parametro.find_by(account_id: @account.id, clave: PARAMETRO_VENTANA)&.valor
    valor.presence&.to_i&.minutes || VENTANA_POR_DEFECTO_MINUTOS.minutes
  end
end
