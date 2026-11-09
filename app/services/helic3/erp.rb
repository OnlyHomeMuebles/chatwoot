# frozen_string_literal: true

# Fachada del modulo ERP: normaliza la cedula (ERP-10) y es el interruptor que decide
# con quien se habla (ERP-04). El consumidor depende de esta fachada, nunca de un
# adaptador concreto.
module Helic3::Erp
  # El modulo no esta bien configurado: modo desconocido o faltan credenciales de Siesa.
  class ConfiguracionInvalida < StandardError; end

  # El ERP no esta disponible (desactivado, o Siesa no respondio): NUNCA debe tumbar una
  # radicacion; el que lo use continua a mano.
  class NoDisponible < StandardError; end

  MODOS = %w[desactivado simulado siesa].freeze
  # Los modos en los que el ERP responde (todos menos desactivado). Una sola fuente de
  # verdad: agregar un modo a MODOS lo refleja aqui sin tocar habilitado?.
  MODOS_ACTIVOS = (MODOS - %w[desactivado]).freeze

  # ERP-16: el modo y la conexion con Siesa HUB se configuran en Super Admin > Settings >
  # Helic3 · ERP Siesa (installation_configs, leidos por GlobalConfig, como la llave de
  # OpenAI de CFG-01). Una sola fuente de verdad: no hay respaldo en variables de entorno.
  # Son conexion e infraestructura, NO reglas de negocio: erp_meses_compras, erp_cache_horas
  # y la ventana de doble radicacion siguen en Parametros de la cuenta.
  CLAVE_MODO = 'HELIC3_ERP_MODO'
  CLAVE_BASE_URL = 'HELIC3_SIESA_HUB_BASE_URL'
  CLAVE_CLIENT_ID = 'HELIC3_SIESA_HUB_CLIENT_ID'
  CLAVE_CONNI_KEY = 'HELIC3_SIESA_HUB_CONNI_KEY'
  CLAVE_CONNI_TOKEN = 'HELIC3_SIESA_HUB_CONNI_TOKEN'
  CLAVE_ID_COMPANIA = 'HELIC3_SIESA_HUB_ID_COMPANIA'
  CLAVE_CONSULTA_CLIENTES = 'HELIC3_SIESA_HUB_CONSULTA_CLIENTES'
  CLAVE_CONSULTA_COMPRAS = 'HELIC3_SIESA_HUB_CONSULTA_COMPRAS'
  # ERP-05: dos consultas, clientes (nombre y contacto de cualquier cedula) y compras (una o
  # varias, separadas por coma).
  CLAVES_SIESA = [
    CLAVE_BASE_URL, CLAVE_CLIENT_ID, CLAVE_CONNI_KEY, CLAVE_CONNI_TOKEN,
    CLAVE_ID_COMPANIA, CLAVE_CONSULTA_CLIENTES, CLAVE_CONSULTA_COMPRAS
  ].freeze

  module_function

  # Deja la cedula lista para consultar y para usar como clave de cache: solo digitos,
  # sin el digito de verificacion (que en Colombia va despues de un guion). Ejemplos:
  #   '1.032.456.789' -> '1032456789'
  #   '900.123.456-7' -> '900123456'  (se descarta el DV '7')
  # Devuelve nil si quedan menos de 5 o mas de 15 digitos: no es una cedula/NIT valido
  # y no vale la pena gastar una consulta al ERP con eso.
  def normalizar_cedula(valor)
    # El DV es UN digito despues de un guion al final (900.123.456-7): se descarta solo
    # ese. Un guion en otra posicion (p. ej. usado como separador) NO corta la cedula.
    sin_dv = valor.to_s.strip.sub(/-\d\z/, '')
    digitos = sin_dv.gsub(/\D/, '')
    return nil if digitos.length < 5 || digitos.length > 15

    digitos
  end

  # Modo de operacion, desde Super Admin. Sin fila (o vacio): DESACTIVADO, para que en
  # produccion nunca responda el simulado con clientes inventados; se enciende a proposito.
  # GlobalConfig se limpia al guardar la pagina: el cambio aplica en la siguiente consulta.
  def modo
    GlobalConfig.get_value(CLAVE_MODO).to_s.strip.downcase.presence || 'desactivado'
  end

  # Si el modulo esta encendido (simulado o siesa). El frontend muestra el boton de
  # consulta solo cuando esto es true. Nota: en modo siesa indica el MODO, no que las
  # credenciales esten completas; el endpoint (ERP-08) captura tanto ConfiguracionInvalida
  # como NoDisponible y responde 503 sin tumbar la radicacion.
  def habilitado?
    MODOS_ACTIVOS.include?(modo)
  end

  # El adaptador segun el modo. Quien lo use debe chequear habilitado? antes; si se
  # llama estando desactivado, levanta NoDisponible en vez de devolver algo usable.
  def adapter
    case modo
    when 'simulado' then SimulatedAdapter.new
    when 'siesa' then adaptador_siesa
    when 'desactivado'
      raise NoDisponible, "el modulo ERP esta desactivado (#{CLAVE_MODO}=desactivado)"
    else
      raise ConfiguracionInvalida, "#{CLAVE_MODO} desconocido: '#{modo}' (usa: #{MODOS.join(', ')})"
    end
  end

  # En modo siesa exige TODA la conexion. Nombra la primera clave que falta, sin imprimir
  # ningun valor (son secretos).
  def adaptador_siesa
    conexion = CLAVES_SIESA.index_with { |clave| GlobalConfig.get_value(clave).to_s.strip }
    faltante = CLAVES_SIESA.find { |clave| conexion[clave].empty? }
    if faltante
      raise ConfiguracionInvalida,
            "falta #{faltante} para el ERP Siesa (Super Admin > Settings > Helic3 · ERP Siesa)"
    end

    Helic3::Erp::SiesaHubAdapter.new(
      cliente: Helic3::Erp::SiesaHubCliente.new(
        base_url: conexion[CLAVE_BASE_URL], client_id: conexion[CLAVE_CLIENT_ID],
        conni_key: conexion[CLAVE_CONNI_KEY], conni_token: conexion[CLAVE_CONNI_TOKEN],
        id_compania: conexion[CLAVE_ID_COMPANIA]
      ),
      consulta_clientes: conexion[CLAVE_CONSULTA_CLIENTES],
      consultas_compras: conexion[CLAVE_CONSULTA_COMPRAS].split(',').map(&:strip).reject(&:empty?)
    )
  end
end
