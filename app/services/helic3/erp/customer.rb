# frozen_string_literal: true

# Cliente tal como lo devuelve el ERP. Objeto de valor inmutable.
# ciudad y direccion (ERP-10) son opcionales: la ciudad decide si la garantia va a
# visita tecnica; la direccion es a donde se recoge o se visita.
Helic3::Erp::Customer = Data.define(:cedula, :nombre, :email, :telefono, :ciudad, :direccion) do
  def initialize(cedula:, nombre:, email: nil, telefono: nil, ciudad: nil, direccion: nil)
    super
  end
end
