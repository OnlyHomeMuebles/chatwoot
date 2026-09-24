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
  # B2 (revisión de Jhan): se usa Inbox#out_of_office?, que resuelve el día y la hora
  # con la ZONA HORARIA de la bandeja (working_hours.today). El cálculo manual con
  # Time.current.wday tomaba la zona de la app (UTC por defecto), así que entre las
  # 19:00 y las 23:59 de Bogotá tomaba el horario del día siguiente. out_of_office?
  # ya contempla working_hours_enabled?, así que no hace falta chequearlo aparte.
  def fuera_de_horario?
    return false unless @agente&.horario == 'horario_atencion'

    @inbox&.out_of_office? || false
  end

  def tope_de_respuestas?
    tope = @agente&.max_respuestas
    tope.present? && @respuestas_previas >= tope
  end

  def motivo_tope
    "alcanzó el máximo de #{@agente.max_respuestas} respuestas de la IA"
  end
end
