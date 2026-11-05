# frozen_string_literal: true

# Cambio de etapas de la PQR a 3 (Nuevo / En gestion / Solucionado): la etapa
# INICIAL con la que nace un expediente deja de identificarse por el texto del
# codigo ('nueva') y pasa a marcarse con este flag. Asi Karen puede renombrar la
# etapa inicial desde el admin sin romper la radicacion (riesgo 1 de la revision
# del #127: la etapa inicial sale de un flag del catalogo, no del texto).
#
# Indice unico parcial: a lo sumo UNA etapa inicial por cuenta (defensa en
# profundidad; el "al menos una" lo garantiza la siembra/migracion de datos).
class AgregaInicialAEtapasPqrHelic3 < ActiveRecord::Migration[7.2]
  def change
    add_column :helic3_catalogo_etapas_pqr, :inicial, :boolean, default: false, null: false
    add_index :helic3_catalogo_etapas_pqr, :account_id,
              unique: true, where: 'inicial', name: 'idx_h3_etapa_inicial_unica'
  end
end
