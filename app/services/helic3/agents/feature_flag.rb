# frozen_string_literal: true

# H3A-12: feature flag por cuenta que decide si el runner arma los agentes desde
# la base de datos (H3A-08) o usa las clases actuales. Es la red de seguridad del
# despliegue: apagado, el comportamiento es el de hoy.
#
# L-09 (lineamientos OSS): toda capacidad nueva de IA entra APAGADA por defecto.
# El flag vive como parametro de la cuenta (tabla propia helic3_catalogo_parametros),
# NO en config/features.yml, porque L-15 solo permite tocar config/routes.rb de
# upstream. Ausente o distinto de 'true' => apagado.
#
# Prender: poner el parametro 'agentes_desde_bd' = 'true' para la cuenta, sin
# desplegar. Apagar: ponerlo en 'false' o borrarlo -> vuelve a las clases.
module Helic3::Agents::FeatureFlag
  CLAVE_AGENTES_DESDE_BD = 'agentes_desde_bd'

  module_function

  # ¿el runner de esta cuenta lee los agentes desde la base de datos?
  # Usa el lector canonico valor_booleano (ActiveModel::Type::Boolean): asi '1',
  # 'True', 't' u 'on' escritos en el panel prenden la bandera, en vez de quedar
  # apagados en silencio como haria un '== true' seco (B2 de la revision de Jhan).
  def agentes_desde_bd?(account)
    return false if account.nil?

    parametro = Helic3::Catalogo::Parametro.find_by(account: account, clave: CLAVE_AGENTES_DESDE_BD)
    parametro&.valor_booleano || false
  end
end
