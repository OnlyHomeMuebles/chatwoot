# frozen_string_literal: true

# COR-01: siembra las 7 plantillas de correo (6 por proceso + cierre de caso)
# y los parametros de remitente/firma/pie, patron SIE-01 (ver
# siembra_helic3_formatos.rb): el seeder es idempotente, asi que es seguro
# aunque SIE-01 ya haya sembrado el resto de catalogos.
class SiembraHelic3PlantillasCorreo < ActiveRecord::Migration[7.2]
  def up
    Helic3::PlantillaCorreo.reset_column_information
    Account.find_each { |cuenta| Helic3::Catalogo::SeederService.new(cuenta).sembrar! }
  end

  def down
    say 'COR-01 no revierte la siembra: las plantillas de correo pueden tener ediciones de Karen.'
  end
end
