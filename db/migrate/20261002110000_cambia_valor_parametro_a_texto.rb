# frozen_string_literal: true

# PRM: los parametros guardaban valores cortos (15, true, un link) en una columna
# `valor :string` (tope 255 por ApplicationRecord). Los mensajes del agente que
# edita Karen son largos (recoleccion ~400), asi que la columna pasa a `text`
# (tope 20_000 via ApplicationRecord). No toca el modelo: el validador dinamico
# ya sube el limite al ver el tipo text.
#
# Timestamp a proposito ANTERIOR al de la siembra de SIE-01 (20261002120000): la
# columna debe ser `text` ANTES de que cualquier migracion de siembra intente
# insertar un mensaje largo, o reventaria el arranque (start.sh con set -e).
class CambiaValorParametroATexto < ActiveRecord::Migration[7.2]
  def up
    change_column :helic3_catalogo_parametros, :valor, :text
  end

  def down
    change_column :helic3_catalogo_parametros, :valor, :string
  end
end
