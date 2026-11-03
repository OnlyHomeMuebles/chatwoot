# El porque de fondo de una devolucion (distinto al de una garantia, aunque
# el detalle fisico y el proceso de atencion compartan el mismo vocabulario
# -- ver la migracion 20261019190000).
# == Schema Information
#
# Table name: helic3_catalogo_motivos_devolucion
#
#  id         :bigint           not null, primary key
#  activo     :boolean          default(TRUE), not null
#  codigo     :string           not null
#  nombre     :string           not null
#  posicion   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  idx_h3cat_motivos_devolucion_account         (account_id)
#  idx_h3cat_motivos_devolucion_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::MotivoDevolucion < ApplicationRecord
  self.table_name = 'helic3_catalogo_motivos_devolucion'

  include Helic3::Catalogo::Comun
end
