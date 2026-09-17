# Namespace de los catalogos de clasificacion del modulo de PQR y Garantias
# (CAT-01). El prefijo de tabla se resuelve aqui una sola vez: todo modelo
# bajo Helic3::Catalogo mapea a una tabla helic3_catalogo_*.
#
# Los modelos con plural irregular en espanol (MotivoPqr, EtapaPqr, etc.)
# declaran su tabla explicita, porque Rails pluralizaria el nombre en ingles
# ("motivo_pqrs", "cobertura_ciudads") y la tabla quedaria mintiendo.
module Helic3::Catalogo
  def self.table_name_prefix
    'helic3_catalogo_'
  end
end
