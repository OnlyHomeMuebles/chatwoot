# frozen_string_literal: true

# Cliente tal como lo devuelve el ERP. Objeto de valor inmutable.
Helic3::Erp::Customer = Data.define(:cedula, :nombre, :email, :telefono) do
  def initialize(cedula:, nombre:, email: nil, telefono: nil)
    super
  end
end
