# frozen_string_literal: true

# MIG-01 (requisito técnico 8): corrige la errata del detalle tipificado sembrado como
# "Chapilla leventada". Solo cambia el nombre (el código chapilla_leventada se queda
# igual) y solo si sigue con la errata, así que es idempotente y no pisa otra edición.
class RenombraChapillaLevantada < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL.squish
      UPDATE helic3_catalogo_detalles_tipificados
      SET nombre = 'Chapilla levantada', updated_at = NOW()
      WHERE codigo = 'chapilla_leventada' AND nombre = 'Chapilla leventada'
    SQL
  end

  def down; end
end
