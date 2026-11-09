# frozen_string_literal: true

# ERP-06/T2: siembra el parametro ventana_doble_radicacion_minutos (10) en el
# despliegue (patron SIE-01: cada PR que agrega filas trae su migracion de
# siembra, nunca por consola/rake), mismo patron que
# 20261028120100_siembra_erp_cache_horas.rb. El seeder es idempotente (solo
# CREA lo que falta, no pisa ediciones), asi que es seguro aunque SIE-01 ya
# haya sembrado el resto.
class SiembraVentanaDobleRadicacion < ActiveRecord::Migration[7.2]
  def up
    Account.find_each { |cuenta| Helic3::Catalogo::SeederService.new(cuenta).sembrar! }
  end

  def down
    say 'ERP-06/T2 no revierte la siembra del parametro ventana_doble_radicacion_minutos.'
  end
end
