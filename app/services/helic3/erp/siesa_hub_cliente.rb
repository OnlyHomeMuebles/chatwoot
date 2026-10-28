# frozen_string_literal: true

# ERP-05: cliente HTTP de Siesa HUB. Hace el GET a estandar/consulta/v3 con las
# credenciales en headers y el filtro en `parametros`, y devuelve el JSON parseado.
# El ERP nunca bloquea: los fallos salen como ErrorConsulta y el consumidor sigue a mano.
class Helic3::Erp::SiesaHubCliente
  class ErrorConsulta < StandardError; end

  RUTA = 'siesahub/siesa/estandar/consulta/v3'
  TIMEOUT = 15 # Jhan: llamada sincrona, timeout corto
  # shortcut: trae solo la 1ra pagina (tam_pag lineas). Si un cliente supera tam_pag lineas de
  # compra en la ventana, las de mas se truncan en silencio; paginar (numPag++) queda para ERP-06.

  def initialize(base_url:, client_id:, conni_key:, conni_token:, id_compania:)
    @base_url = base_url.to_s.chomp('/')
    @client_id = client_id
    @conni_key = conni_key
    @conni_token = conni_token
    @id_compania = id_compania
  end

  # @param descripcion [String] nombre de la consulta (ej. API_v2_Ventas_Facturas_DesdePedido)
  # @param parametros [String] filtro SQL (ej. f200_nit_fact=''123'' and f350_fecha >= ''2026-01-01'')
  # @return [Hash] el JSON de Siesa
  def consultar(descripcion:, parametros:, tam_pag: 100)
    respuesta = HTTParty.get(
      "#{@base_url}/#{RUTA}",
      headers: { 'client_id' => @client_id, 'ConniKey' => @conni_key, 'ConniToken' => @conni_token },
      query: { idCompania: @id_compania, descripcion: descripcion,
               paginacion: "numPag=1|tamPag=#{tam_pag}", parametros: parametros },
      timeout: TIMEOUT
    )
    cuerpo = respuesta.parsed_response
    raise ErrorConsulta, 'Siesa devolvio una respuesta no-JSON' unless cuerpo.is_a?(Hash)

    # "Sin registros" (codigo 1) llega como HTTP 400 pero es un resultado valido (vacio). Se
    # decide por el codigo del cuerpo, NO por el 400: cualquier otro 400 (credenciales, SQL
    # malo) o 5xx si es error, para no enmascararlo como "no hay compras".
    return cuerpo if respuesta.success? || cuerpo['codigo'].to_s == '1'

    raise ErrorConsulta, "Siesa respondio HTTP #{respuesta.code} (codigo #{cuerpo['codigo']})"
  rescue SocketError, Timeout::Error, HTTParty::Error => e
    raise ErrorConsulta, "fallo la consulta a Siesa: #{e.class}"
  end
end
