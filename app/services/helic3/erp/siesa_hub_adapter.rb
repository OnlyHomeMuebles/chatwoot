# frozen_string_literal: true

# ERP-05: adaptador real del ERP contra Siesa HUB. Implementa el contrato Helic3::Erp::Base.
#
# `find_customer` consulta el MAESTRO DE CLIENTES (terceros) por cedula: trae el nombre de
# cualquier cliente, tenga compras o no. `invoices` consulta las FACTURAS (una o varias
# fuentes) por cedula+fecha; la ventana (`desde`) la decide el cache por cuenta (parametro
# erp_meses_compras), no una constante ni una variable de entorno. `invoice`/`account_statement`
# no los usa ningun consumidor y heredan el NotImplementedError de Base.
class Helic3::Erp::SiesaHubAdapter < Helic3::Erp::Base
  def initialize(cliente: nil, consultas_compras: nil, consulta_clientes: nil)
    @cliente = cliente || cliente_desde_env
    @consultas_compras = consultas_compras || fuentes_desde_env
    @consulta_clientes = consulta_clientes || ENV.fetch('SIESA_HUB_CONSULTA_CLIENTES')
  end

  # Facturas por cedula desde la fecha `desde` (ISO). Concatena las fuentes; si una responde
  # "sin registros" (codigo:1) el parser devuelve [], que es un resultado valido, no un error.
  def invoices(cedula:, desde:)
    @consultas_compras.flat_map do |consulta|
      respuesta = @cliente.consultar(descripcion: consulta, parametros: filtro_compras(cedula, desde))
      Helic3::Erp::SiesaFacturas.parsear(respuesta)
    end
  end

  # Cliente desde la consulta de clientes (maestro de terceros), filtrada por cedula (campo `id`).
  # Trae identificacion, nombre y contacto (telefono, correo, direccion) para CUALQUIER cedula,
  # tenga compras o no. La ciudad viene como codigo y queda nil (follow-up). nil si no esta.
  def find_customer(cedula:)
    respuesta = @cliente.consultar(descripcion: @consulta_clientes, parametros: filtro_clientes(cedula))
    Helic3::Erp::SiesaClientes.parsear(respuesta, cedula: solo_digitos(cedula))
  end

  private

  # La cedula se sanea a solo digitos aqui mismo (no se confia en el llamador): es lo unico que
  # entra al SQL de `parametros` desde fuera, asi no se puede inyectar. `desde` es interno (fecha
  # iso que calcula el cache). Comillas simples dobles = una comilla para Siesa.
  def filtro_compras(cedula, desde)
    "f200_nit_fact=''#{solo_digitos(cedula)}'' and f350_fecha >= ''#{desde}''"
  end

  def filtro_clientes(cedula)
    "id=''#{solo_digitos(cedula)}''"
  end

  def solo_digitos(cedula)
    cedula.to_s.gsub(/\D/, '')
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
