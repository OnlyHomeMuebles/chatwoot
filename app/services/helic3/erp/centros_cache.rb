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

  module_function

  # @return [Array<Hash>] centros parseados ({compania:, id:, nombre:, regional:, activo:}); [] si no hay.
  def lista
    cacheada = Rails.cache.read(CLAVE)
    return cacheada if cacheada

    centros = traer
    Rails.cache.write(CLAVE, centros, expires_in: VIGENCIA) if centros.any?
    centros
  end

  # trae y parsea la lista desde el adaptador; [] si el adaptador no ofrece centros (consulta
  # sin configurar o modo simulado).
  def traer
    respuesta = Helic3::Erp.adapter.centros
    respuesta ? Helic3::Erp::SiesaCentros.parsear(respuesta) : []
  end
end
