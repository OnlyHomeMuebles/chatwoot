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
# La VERSION vive en Redis (compartido entre procesos), NO las filas (decision del
# tech lead, PR #78). Puma (CRUD) y Sidekiq (runner) corren en contenedores separados
# con su propio Rails.cache; si la version viviera en Rails.cache la invalidacion no
# cruzaria de proceso. Las filas siguen en Rails.cache POR PROCESO: asi no se
# serializan objetos ActiveRecord en un store compartido (una entrada desfasada por
# un deploy queda local y se cura en 30s, no envenena a todos). El contador es
# atomico (Redis incr): no depende del reloj.
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

  # sube la version de la cuenta en Redis (compartido): invalida todas sus bandejas
  # en el siguiente mensaje, en TODOS los procesos. incr es atomico y sin reloj.
  def invalidar(account_id)
    return if account_id.blank?

    Redis::Alfred.incr(clave_version(account_id))
  rescue StandardError => e
    Rails.logger.warn("[Helic3][cache] no se pudo invalidar cta=#{account_id}: #{e.message}")
  end

  def clave_agentes(inbox)
    "helic3:agentes:cta#{inbox.account_id}:v#{version(inbox.account_id)}:inbox#{inbox.id}"
  end

  # la version vive en Redis (compartido entre procesos). Si Redis falla, se
  # devuelve un valor IRREPETIBLE para forzar un MISS (consultar la BD) en vez de
  # servir una entrada vieja a todos los procesos: misma degradacion que agentes_para.
  def version(account_id)
    Redis::Alfred.get(clave_version(account_id)) || '0'
  rescue StandardError
    SecureRandom.hex(4)
  end

  def clave_version(account_id)
    "helic3:agentes:ver:cta#{account_id}"
  end
end
