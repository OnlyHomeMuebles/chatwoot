# Namespace raíz del módulo Helic3. Define el prefijo de tabla para los modelos
# propios (p. ej. Helic3::Ticket -> helic3_tickets). Los modelos que fijan
# self.table_name explícitamente (Helic3::Knowledge::*) no se ven afectados.
module Helic3
  def self.table_name_prefix
    'helic3_'
  end
end
