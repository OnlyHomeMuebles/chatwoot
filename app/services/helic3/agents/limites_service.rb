# frozen_string_literal: true

# H3A-11: limites de ejecucion del agente ACTIVO, evaluados ANTES de responder.
#
# - horario: si el agente atiende solo en horario de atencion y el inbox esta
#   cerrado ahora, no responde -> la conversacion queda sin asignar a IA (crit 2).
# - max_respuestas: si la IA ya respondio el tope de veces en la conversacion,
#   deriva al equipo con su mensaje_handoff y team_id (crit 1).
#
# El motivo de cada corte lo registra el llamador en el log (crit 3).
#
# NOTA (hueco declarado): confianza_minima NO se aplica aqui. El runner (gem
# ai-agents) no produce un puntaje de confianza, asi que no hay valor que comparar.
# Queda pendiente de definir con Jhan una fuente de confianza (ver PENDIENTES.md).
class Helic3::Agents::LimitesService
  # accion: :responder | :dejar_sin_ia | :derivar_equipo
  Decision = Struct.new(:accion, :motivo, keyword_init: true)

  def initialize(agente:, inbox:, respuestas_previas:)
    @agente = agente
    @inbox = inbox
    @respuestas_previas = respuestas_previas.to_i
  end

  def evaluar
    return Decision.new(accion: :dejar_sin_ia, motivo: 'fuera del horario de atención') if fuera_de_horario?
    return Decision.new(accion: :derivar_equipo, motivo: motivo_tope) if tope_de_respuestas?

    Decision.new(accion: :responder, motivo: nil)
  end

  private

  # solo aplica a agentes marcados 'horario_atencion'; 'siempre' (o nulo) no se corta.
  def fuera_de_horario?
    return false unless @agente&.horario == 'horario_atencion'
    return false unless @inbox&.working_hours_enabled?

    horario_hoy = @inbox.working_hours.find_by(day_of_week: Time.current.wday)
    horario_hoy.present? && horario_hoy.closed_now?
  end

  def tope_de_respuestas?
    tope = @agente&.max_respuestas
    tope.present? && @respuestas_previas >= tope
  end

  def motivo_tope
    "alcanzó el máximo de #{@agente.max_respuestas} respuestas de la IA"
  end
end
