# frozen_string_literal: true

# ERP-05: siembra el parametro erp_meses_compras (12) en el despliegue (patron SIE-01: cada
# PR que agrega filas trae su migracion de siembra, nunca por consola/rake). El seeder es
# idempotente (solo CREA lo que falta, no pisa ediciones), asi que es seguro re-correrlo.
class SiembraErpMesesCompras < ActiveRecord::Migration[7.2]
  def up
    Account.find_each { |cuenta| Helic3::Catalogo::SeederService.new(cuenta).sembrar! }
  end

  def down
    say 'ERP-05 no revierte la siembra del parametro erp_meses_compras.'
  end
end
