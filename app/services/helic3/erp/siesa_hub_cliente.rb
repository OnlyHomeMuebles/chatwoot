# frozen_string_literal: true

# ERP-05: cliente HTTP de Siesa HUB. Hace el GET a estandar/consulta/v3 con las
# credenciales en headers y el filtro en `parametros`, y devuelve el JSON parseado.
# El ERP nunca bloquea: los fallos salen como ErrorConsulta y el consumidor sigue a mano.
class Helic3::Erp::SiesaHubCliente
  # El contrato del modulo habla en NoDisponible; ErrorConsulta ES un NoDisponible para que el
  # consumidor lo trate igual (503 / seguir a mano) sin conocer esta clase.
  class ErrorConsulta < Helic3::Erp::NoDisponible; end

  # Fallo transitorio (red, 429, 5xx): vale la pena reintentar. Interno, no sale del cliente.
  class Reintentable < StandardError; end
  private_constant :Reintentable

  RUTA = 'siesahub/siesa/estandar/consulta/v3'
  TIMEOUT = 15 # Jhan: llamada sincrona, timeout corto
  REINTENTOS = 2 # reintentos extra ante fallo transitorio (3 intentos en total)
  ESPERA_BASE = 0.5 # segundos; backoff lineal entre reintentos
  # Fallos de red que valen reintento (ECONNREFUSED es SystemCallError; SSL y JSON crudo tambien).
  REINTENTABLES = [SocketError, Timeout::Error, HTTParty::Error, SystemCallError,
                   OpenSSL::SSL::SSLError, JSON::ParserError].freeze
  # shortcut: trae solo la 1ra pagina (tam_pag lineas). Si llega llena, avisa (puede faltar);
  # paginar (numPag++) queda para un ticket aparte del agente de compras.

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
    intento = 0
    begin
      pedir(descripcion, parametros, tam_pag)
    rescue Reintentable, *REINTENTABLES => e
      intento += 1
      if intento <= REINTENTOS
        sleep(ESPERA_BASE * intento)
        retry
      end
      raise ErrorConsulta, "Siesa no responde tras #{intento + 1} intentos (#{e.class})"
    end
  end

  private

  def pedir(descripcion, parametros, tam_pag)
    respuesta = HTTParty.get(
      "#{@base_url}/#{RUTA}",
      headers: { 'client_id' => @client_id, 'ConniKey' => @conni_key, 'ConniToken' => @conni_token },
      query: { idCompania: @id_compania, descripcion: descripcion,
               paginacion: "numPag=1|tamPag=#{tam_pag}", parametros: parametros },
      timeout: TIMEOUT
    )
    # 429 y 5xx son transitorios: se reintentan ANTES de mirar el cuerpo (un 5xx suele traer
    # HTML o nada, no JSON; si se parseara primero se trataria como "no-JSON" definitivo).
    raise Reintentable, "HTTP #{respuesta.code}" if respuesta.code == 429 || respuesta.code >= 500

    cuerpo = respuesta.parsed_response
    raise ErrorConsulta, 'Siesa devolvio una respuesta no-JSON' unless cuerpo.is_a?(Hash)

    # "Sin registros" (codigo 1) llega como HTTP 400 pero es un resultado valido (vacio). Se
    # decide por el codigo del cuerpo, NO por el 400: cualquier otro 400 (credenciales, SQL
    # malo) es error definitivo (no se reintenta).
    return avisar_si_llena(cuerpo, tam_pag) if respuesta.success? || cuerpo['codigo'].to_s == '1'

    raise ErrorConsulta, "Siesa respondio HTTP #{respuesta.code} (codigo #{cuerpo['codigo']})"
  end

  # Si la pagina llega llena puede haber compras sin traer (solo se pide la 1ra). Se avisa en el
  # log; no es error (el contrato trae lo que haya), pero deja rastro para cuando toque paginar.
  def avisar_si_llena(cuerpo, tam_pag)
    filas = cuerpo.dig('detalle', 'Table')
    if filas.is_a?(Array) && filas.size >= tam_pag
      Rails.logger.warn("[ERP-05] Siesa devolvio la pagina llena (#{filas.size} lineas); pueden faltar compras (paginar)")
    end
    cuerpo
  end
end
