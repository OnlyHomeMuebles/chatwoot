# frozen_string_literal: true

# Presupuesto de garantía: sobre el calendario hábil, aplica la regla confirmada
# por Only Home el 24 de agosto de 2026: hay un único presupuesto de días hábiles
# para toda la garantía, el reloj NO se reinicia al cambiar de estado, y los plazos
# por etapa son topes dentro de ese presupuesto.
#
# No lee la tabla de parámetros directamente (eso es de CAT-02): recibe los
# parámetros ya resueltos, para poder instanciarse y probarse solo. Ningún número
# de negocio vive aquí.
class Helic3::PresupuestoGarantia
  def initialize(fecha_inicio:, plazo_etapa_vigente:, parametros:,
                 calendario: Helic3::CalendarioHabil.new, hoy: Helic3::CalendarioHabil.hoy)
    @fecha_inicio = fecha_inicio.to_date
    @plazo_etapa_vigente = plazo_etapa_vigente
    @parametros = parametros
    @calendario = calendario
    @hoy = hoy.to_date
  end

  # Días hábiles consumidos desde el inicio de la garantía hasta hoy.
  def consumidos
    @consumidos ||= @calendario.dias_habiles_entre(@fecha_inicio, @hoy)
  end

  # Días hábiles que quedan del presupuesto total. Puede quedar negativo si la
  # garantía ya se pasó del presupuesto (señal de vencido).
  def saldo
    @parametros.total_dias - consumidos
  end

  # Fecha que se le promete al cliente para la etapa vigente. El plazo de la etapa
  # nunca puede exceder el saldo: si la etapa son 20 días pero solo quedan 7, se
  # promete a 7 (nunca a menos de 0).
  def fecha_etapa_vigente
    dias = saldo.clamp(0, @plazo_etapa_vigente)
    @calendario.sumar_dias_habiles(@hoy, dias)
  end

  # Semáforo calculado contra el saldo total, no contra el plazo de la etapa
  # vigente. Los umbrales salen de los parámetros.
  def semaforo
    restante = saldo
    if restante >= @parametros.umbral_verde
      :verde
    elsif restante >= @parametros.umbral_amarillo
      :amarillo
    else
      :rojo
    end
  end

  # Estado completo del presupuesto para la etapa vigente.
  def estado
    {
      consumidos: consumidos,
      saldo: saldo,
      fecha_etapa_vigente: fecha_etapa_vigente,
      semaforo: semaforo
    }
  end
end
