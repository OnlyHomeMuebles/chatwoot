# frozen_string_literal: true

# H3A-06: cache de la configuracion de agentes por (account_id, inbox_id), con
# expiracion corta. El runner (H3A-08) la consulta en cada mensaje en vez de
# pegarle a la base.
#
# Invalidacion por VERSION de cuenta: al guardar o pausar un agente (o cambiar sus
# bandejas) se sube la version de la cuenta y las claves viejas quedan huerfanas
# (expiran solas por TTL). Asi no hay que enumerar bandejas ni acertar la clave
# exacta al invalidar, y cubre create/update/pausa/borrado y cambios de bandeja.
#
# La metrica de aciertos (HIT/MISS) queda en el log (criterio 3).
module Helic3::Agents::ConfigCache
  TTL = 30.seconds

  module_function

  # agentes activos para la bandeja, desde cache. Si la cache falla, cae a la BD
  # sin romper (la cache es una optimizacion, no una fuente de verdad).
  def agentes_para(inbox)
    hubo_acierto = true
    filas = Rails.cache.fetch(clave_agentes(inbox), expires_in: TTL) do
      hubo_acierto = false
      Helic3::Agente.activos_para(inbox).to_a
    end
    Rails.logger.info(
      "[Helic3][cache] agentes cta=#{inbox.account_id} inbox=#{inbox.id} #{hubo_acierto ? 'HIT' : 'MISS'}"
    )
    filas
  rescue StandardError => e
    Rails.logger.warn("[Helic3][cache] fallo al leer (#{e.message}); se consulta la BD")
    Helic3::Agente.activos_para(inbox).to_a
  end

  # sube la version de la cuenta: invalida todas sus bandejas en el siguiente mensaje
  def invalidar(account_id)
    return if account_id.blank?

    Rails.cache.write(clave_version(account_id), Time.now.to_f.to_s, expires_in: 1.day)
  rescue StandardError => e
    Rails.logger.warn("[Helic3][cache] no se pudo invalidar cta=#{account_id}: #{e.message}")
  end

  def clave_agentes(inbox)
    "helic3:agentes:cta#{inbox.account_id}:v#{version(inbox.account_id)}:inbox#{inbox.id}"
  end

  def version(account_id)
    Rails.cache.read(clave_version(account_id)) || '0'
  end

  def clave_version(account_id)
    "helic3:agentes:ver:cta#{account_id}"
  end
end
