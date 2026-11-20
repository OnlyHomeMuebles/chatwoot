# frozen_string_literal: true

# ERP-18b: cache de la lista de centros de operacion (tiendas). A diferencia de
# Helic3::Erp::Cache (por cuenta + cedula), esta lista es GLOBAL: la misma para todas las
# cedulas y cuentas, se pide UNA vez y se reusa. Por eso NO cabe en el cache por cedula
# (justificacion para el PR); vive en Rails.cache con una clave unica y un tiempo largo (las
# tiendas casi no cambian). No cachea la lista vacia: si la consulta aun no esta configurada o
# fallo, se reintenta en la siguiente, para que configurarla tome efecto enseguida (no en 7 dias).
module Helic3::Erp::CentrosCache
  CLAVE = 'helic3/erp/centros_operacion'
  VIGENCIA = 7.days
  VIGENCIA_FALLO = 5.minutes # tras un fallo de Siesa: no reintentar (ni esperar el timeout) por cedula

  module_function

  # @param adaptador el adaptador del ERP; se pasa cuando el llamador ya lo resolvio (el cache por
  #   cedula), para no resolverlo dos veces. Se resuelve solo en miss, nunca en cache hit.
  # @return [Array<Hash>] centros parseados ({compania:, id:, nombre:, regional:, activo:}); [] si no hay.
  def lista(adaptador = nil)
    cacheada = Rails.cache.read(CLAVE)
    return cacheada if cacheada

    centros = traer(adaptador || Helic3::Erp.adapter)
    Rails.cache.write(CLAVE, centros, expires_in: VIGENCIA) if centros.any?
    centros
  rescue Helic3::Erp::NoDisponible => e
    # Jhan #173: el nombre del C.O. es un enriquecimiento OPCIONAL; si su consulta falla (Siesa
    # caida/lenta, nombre mal escrito), NO puede tumbar la consulta principal (cliente + facturas,
    # que Cache#desde_adaptador ya trajo). Devuelve [] y cachea el fallo un rato, para no volver a
    # esperar el timeout (~46s) en cada cedula mientras Siesa este caida.
    Rails.logger.warn("[ERP-18b] centros de operacion no disponibles: #{e.message}")
    Rails.cache.write(CLAVE, [], expires_in: VIGENCIA_FALLO)
    []
  end

  # trae y parsea la lista desde el adaptador; [] si el adaptador no ofrece centros (consulta sin
  # configurar o modo simulado). Un fallo de Siesa sube como NoDisponible y lo maneja #lista.
  def traer(adaptador)
    respuesta = adaptador.centros
    respuesta ? Helic3::Erp::SiesaCentros.parsear(respuesta) : []
  end
end
