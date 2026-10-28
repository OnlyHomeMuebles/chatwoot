# frozen_string_literal: true

# ERP-05: adaptador real del ERP contra Siesa HUB. Implementa el contrato Helic3::Erp::Base.
#
# Alcance v1 (doc de Jhan 27-oct): `invoices` trae las facturas + productos por cedula.
# Las FUENTES de compras son una lista de consultas en la config (1 o 2), no una consulta
# fija: cada una devuelve el mismo contrato Invoice y se concatenan. `find_customer` queda
# para la consulta de clientes (pendiente ERP-12); `invoice`/`account_statement` no los usa
# ningun consumidor y heredan el NotImplementedError de Base.
class Helic3::Erp::SiesaHubAdapter < Helic3::Erp::Base
  MESES_DEFECTO = 12 # ventana de busqueda; Jhan: se amarra al periodo de garantia (afinar en ERP-12)

  def initialize(cliente: nil, consultas_compras: nil, desde: nil)
    @cliente = cliente || cliente_desde_env
    @consultas_compras = consultas_compras || fuentes_desde_env
    # Precedencia: inyectado (tests) -> SIESA_HUB_DESDE (ENV, para probar data historica de QA)
    # -> default (ultimos MESES_DEFECTO meses, lo correcto en produccion).
    @desde = desde || ENV['SIESA_HUB_DESDE'].presence || (Date.current << MESES_DEFECTO).iso8601
  end

  # Concatena las facturas de cada fuente. Si una fuente responde "sin registros"
  # (codigo:1) el parser devuelve [], que es un resultado valido, no un error.
  def invoices(cedula:)
    @consultas_compras.flat_map do |consulta|
      respuesta = @cliente.consultar(descripcion: consulta, parametros: filtro(cedula))
      Helic3::Erp::SiesaFacturas.parsear(respuesta)
    end
  end

  # v1 (stopgap): el nombre se saca de la misma respuesta de compras (f200_razon_social_fact),
  # asi la ficha muestra al cliente sin esperar a ERP-12. Ciudad/contacto quedan en nil (eso si
  # necesita la consulta de clientes). nil si no tiene compras (no hay nombre que mostrar).
  # shortcut: repite la consulta de compras solo por el nombre; el cache (ERP-14) la sirve 24h.
  # Upgrade: ERP-12 reemplaza esto por la consulta de clientes real (nombre + ciudad + contacto).
  def find_customer(cedula:)
    respuesta = @cliente.consultar(descripcion: @consultas_compras.first, parametros: filtro(cedula))
    nombre = Helic3::Erp::SiesaFacturas.nombre_cliente(respuesta)
    return nil if nombre.nil?

    Helic3::Erp::Customer.new(cedula: cedula.to_s.gsub(/\D/, ''), nombre: nombre)
  end

  private

  # Filtro SQL de `parametros`: por cedula y por fecha (comillas simples dobles). La cedula se
  # sanea a solo digitos aqui mismo (no se confia en que el llamador la haya normalizado): es
  # lo unico que entra al SQL desde fuera, asi no se puede inyectar por `parametros`. `@desde`
  # es interno (fecha iso). El cache/consumidor ya compara exacto del lado Helic3.
  def filtro(cedula)
    "f200_nit_fact=''#{cedula.to_s.gsub(/\D/, '')}'' and f350_fecha >= ''#{@desde}''"
  end

  def cliente_desde_env
    Helic3::Erp::SiesaHubCliente.new(
      base_url: ENV.fetch('SIESA_HUB_BASE_URL'),
      client_id: ENV.fetch('SIESA_HUB_CLIENT_ID'),
      conni_key: ENV.fetch('SIESA_HUB_CONNI_KEY'),
      conni_token: ENV.fetch('SIESA_HUB_CONNI_TOKEN'),
      id_compania: ENV.fetch('SIESA_HUB_ID_COMPANIA')
    )
  end

  def fuentes_desde_env
    ENV.fetch('SIESA_HUB_CONSULTA_COMPRAS').split(',').map(&:strip)
  end
end
