# frozen_string_literal: true

# Parámetros de negocio del presupuesto de garantía. En producción se llenan desde
# la tabla de parámetros (CAT-02); aquí no vive ningún número de negocio.
#
#   total_dias      Presupuesto total de días hábiles para toda la garantía.
#   umbral_verde    Saldo mínimo (en días hábiles) para que el semáforo sea verde.
#   umbral_amarillo Saldo mínimo para amarillo; por debajo es rojo.
Helic3::ParametrosGarantia = Struct.new(:total_dias, :umbral_verde, :umbral_amarillo, keyword_init: true)

# El constructor desde el catálogo (SEM-01): el Struct deja de ser huérfano.
# Cada ámbito lee su propio juego de claves porque son dos relojes con dos
# escalas: la garantía mide un presupuesto de 30 días y la PQR uno de 15 —
# con una sola escala, la PQR nacería en amarillo y el semáforo no serviría.
class Helic3::ParametrosGarantia
  # error de configuración visible: nombra la clave y la cuenta, nunca un
  # valor por defecto silencioso que después dé un color equivocado
  ParametroFaltante = Class.new(StandardError)

  CLAVES = {
    garantia: {
      total_dias: 'plazo_total_garantia',
      umbral_verde: 'umbral_verde_garantia',
      umbral_amarillo: 'umbral_amarillo_garantia'
    },
    pqr: {
      total_dias: 'plazo_respuesta_pqr',
      umbral_verde: 'umbral_verde_pqr',
      umbral_amarillo: 'umbral_amarillo_pqr'
    }
  }.freeze

  def self.desde_catalogo(account, ambito:)
    claves = CLAVES.fetch(ambito) do
      raise ArgumentError, "ambito desconocido: #{ambito} (validos: #{CLAVES.keys.join(', ')})"
    end

    new(
      total_dias: leer!(account, claves[:total_dias]),
      umbral_verde: leer!(account, claves[:umbral_verde]),
      umbral_amarillo: leer!(account, claves[:umbral_amarillo])
    )
  end

  def self.leer!(account, clave)
    valor = Helic3::Catalogo::Parametro
            .find_by(account_id: account.id, clave: clave)
            &.valor_entero
    return valor if valor

    raise ParametroFaltante, "falta el parametro '#{clave}' en la cuenta #{account.id}"
  end
  private_class_method :leer!
end
