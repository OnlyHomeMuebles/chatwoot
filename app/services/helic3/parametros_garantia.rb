# frozen_string_literal: true

# Parámetros de negocio del presupuesto de garantía. En producción se llenan desde
# la tabla de parámetros (CAT-02); aquí no vive ningún número de negocio.
#
#   total_dias      Presupuesto total de días hábiles para toda la garantía.
#   umbral_verde    Saldo mínimo (en días hábiles) para que el semáforo sea verde.
#   umbral_amarillo Saldo mínimo para amarillo; por debajo es rojo.
Helic3::ParametrosGarantia = Struct.new(:total_dias, :umbral_verde, :umbral_amarillo, keyword_init: true)
