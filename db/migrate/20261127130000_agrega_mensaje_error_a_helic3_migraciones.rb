# frozen_string_literal: true

# MIG-02: por qué falló una corrida (columnas o catálogos faltantes), para que la
# página lo muestre y no deje confirmar.
class AgregaMensajeErrorAHelic3Migraciones < ActiveRecord::Migration[7.2]
  def change
    add_column :helic3_migraciones, :mensaje_error, :text
  end
end
