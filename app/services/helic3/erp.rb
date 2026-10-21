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

  # Credenciales y datos de conexion de Siesa Hub. Son secretos e infraestructura
  # (se configuran en Dokploy), NO valores de negocio: por eso van por ENV y nunca a
  # catalogo ni a Parametro, ni al repositorio.
  VARIABLES_SIESA = %w[
    SIESA_HUB_BASE_URL SIESA_HUB_CLIENT_ID SIESA_HUB_CONNI_KEY
    SIESA_HUB_CONNI_TOKEN SIESA_HUB_ID_COMPANIA SIESA_HUB_CONSULTA_CLIENTES
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

  # Modo de operacion, desde HELIC3_ERP_MODO. Por defecto DESACTIVADO: en produccion
  # nunca puede responder el simulado con clientes inventados; se enciende a proposito.
  def modo
    ENV['HELIC3_ERP_MODO'].to_s.strip.downcase.presence || 'desactivado'
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
      raise NoDisponible, 'el modulo ERP esta desactivado (HELIC3_ERP_MODO=desactivado)'
    else
      raise ConfiguracionInvalida, "HELIC3_ERP_MODO desconocido: '#{modo}' (usa: #{MODOS.join(', ')})"
    end
  end

  # En modo siesa exige TODAS las variables de conexion. Nombra la primera que falta, sin
  # imprimir ningun valor (son secretos). El adaptador real se implementa en ERP-05.
  def adaptador_siesa
    faltante = VARIABLES_SIESA.find { |variable| ENV[variable].to_s.strip.empty? }
    raise ConfiguracionInvalida, "falta la variable #{faltante} para el ERP Siesa" if faltante

    Helic3::Erp::SiesaHubAdapter.new # ERP-05
  rescue NameError => e
    raise unless e.message.include?('SiesaHubAdapter')

    # El adaptador real aun no existe (ERP-05): se devuelve un error controlado del modulo
    # (NoDisponible), no un NameError crudo, para que el consumidor pueda continuar a mano.
    raise NoDisponible, 'el adaptador real de Siesa aun no esta implementado (ERP-05)'
  end
end
