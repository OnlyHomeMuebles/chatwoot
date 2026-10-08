# frozen_string_literal: true

# FMT-04 (parte D): cada proceso de garantia puede sugerir un formato. Columna
# nulable en tabla propia -> no toca upstream. La relacion la edita Karen desde
# el admin de catalogos; el seeder solo la precarga donde este vacia.
class AddFormatoSugeridoToProcesosGarantia < ActiveRecord::Migration[7.0]
  def change
    add_reference :helic3_catalogo_procesos_garantia, :formato_sugerido,
                  null: true, index: { name: 'idx_h3cat_procesos_garantia_formato_sugerido' },
                  foreign_key: { to_table: :helic3_catalogo_formatos, on_delete: :nullify }
  end
end
