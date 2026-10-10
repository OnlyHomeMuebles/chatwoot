# frozen_string_literal: true

# FMT-02: siembra los 4 formatos en el despliegue (patron SIE-01: cada PR que
# agrega filas trae su propia migracion de siembra, nunca por consola/rake). El
# seeder es idempotente (sembrar_fila solo CREA lo que falta, no pisa ediciones),
# asi que es seguro aunque SIE-01 ya haya sembrado el resto de catalogos.
class SiembraHelic3Formatos < ActiveRecord::Migration[7.2]
  def up
    # el seeder quedo cargado antes de que existiera la tabla en este deploy; se
    # refresca para que conozca sus columnas.
    Helic3::Catalogo::Formato.reset_column_information
    Account.find_each { |cuenta| Helic3::Catalogo::SeederService.new(cuenta).sembrar! }
  end

  def down
    say 'FMT-02 no revierte la siembra: los formatos pueden tener plantillas asociadas.'
  end
end
