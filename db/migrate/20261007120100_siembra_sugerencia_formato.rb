# frozen_string_literal: true

# FMT-04: siembra el formato sugerido por proceso (parte D) en el despliegue
# (patron SIE-01: cada PR trae su migracion de siembra). Va DESPUES de agregar la
# columna formato_sugerido_id (20261007120000); ahi el seeder ya puede precargar
# la sugerencia. sembrar! es idempotente y solo llena donde este vacio, asi que no
# pisa lo que Karen haya configurado desde el admin.
class SiembraSugerenciaFormato < ActiveRecord::Migration[7.2]
  def up
    Helic3::Catalogo::ProcesoGarantia.reset_column_information
    Account.find_each { |cuenta| Helic3::Catalogo::SeederService.new(cuenta).sembrar! }
  end

  def down
    say 'FMT-04 no revierte la siembra de la sugerencia de formato.'
  end
end
