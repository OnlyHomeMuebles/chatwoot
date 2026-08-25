# El estado operativo de CADA PRODUCTO de una garantia (decision del 25/08:
# la garantia no tiene estado propio — tiene productos y una condicion de
# cierre). El plazo es un parametro de programacion dentro del presupuesto
# de 30 dias, como dato: visita tecnica 8, recoleccion 15, cambio 20.
# es_terminal marca los desenlaces finales: la garantia cierra cuando todos
# sus productos llegan a un proceso terminal.
# == Schema Information
#
# Table name: helic3_catalogo_procesos_garantia
#
#  id                 :bigint           not null, primary key
#  activo             :boolean          default(TRUE), not null
#  codigo             :string           not null
#  es_terminal        :boolean          default(FALSE), not null
#  nombre             :string           not null
#  plazo_dias_habiles :integer
#  posicion           :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  idx_h3cat_procesos_garantia_account         (account_id)
#  idx_h3cat_procesos_garantia_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::ProcesoGarantia < ApplicationRecord
  # plural espanol explicito: Rails generaria "proceso_garantias"
  self.table_name = 'helic3_catalogo_procesos_garantia'

  include Helic3::Catalogo::Comun

  validates :plazo_dias_habiles, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
