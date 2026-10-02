# frozen_string_literal: true

# PRM (convencion SIE-01 §4.4): este PR agrega filas al seeder (los mensajes del
# agente), asi que trae su propia migracion de siembra. En los entornos donde la
# migracion de SIE-01 YA corrio, no se vuelve a ejecutar, por lo que los mensajes
# nuevos no llegarian ahi; esta migracion los siembra. El seeder es idempotente
# (llave natural por clave): re-llamarlo solo crea lo que falta.
#
# Depende de que `valor` ya sea `text` (migracion 20261002110000, anterior): los
# mensajes largos no caben en string(255).
class SiembraMensajesAgente < ActiveRecord::Migration[7.2]
  def up
    # por si la migracion que cambia la columna corrio en el mismo despliegue
    Helic3::Catalogo::Parametro.reset_column_information

    Account.find_each do |cuenta|
      resumen = Helic3::Catalogo::SeederService.new(cuenta).sembrar!
      say "Cuenta #{cuenta.id} (#{cuenta.name})"
      say("parametros: #{resumen[:parametros]}", true)
    end
  end

  def down
    # No-op a proposito: los parametros pueden estar editados desde el panel y
    # referenciados por la operacion. Revertir borraria datos reales.
    say 'PRM: no se revierte la siembra de mensajes del agente.'
  end
end
