# frozen_string_literal: true

# Estado de cuenta (cartera) de un cliente. Objeto de valor inmutable.
Helic3::Erp::AccountStatement = Data.define(:cedula, :saldo_total, :facturas_pendientes, :al_dia) do
  def initialize(cedula:, saldo_total: 0, facturas_pendientes: 0, al_dia: true)
    super
  end
end
