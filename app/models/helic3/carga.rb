# IND-03 (parcial): una fila por archivo subido en "Carga de Datos". Hoy solo
# el tipo :facturas tiene parser real -- :garantias/:peticiones/:devoluciones
# (IND-04) esperan a que se definan sus columnas con el Dash CX.
# == Schema Information
#
# Table name: helic3_cargas
#
#  id                 :bigint           not null, primary key
#  errores            :jsonb            not null
#  estado             :string           default("procesando"), not null
#  filas_actualizadas :integer          default(0), not null
#  filas_insertadas   :integer          default(0), not null
#  filas_leidas       :integer          default(0), not null
#  filas_omitidas     :integer          default(0), not null
#  modo               :string           not null
#  nombre_archivo     :string           not null
#  tipo               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  usuario_id         :bigint
#
class Helic3::Carga < ApplicationRecord
  self.table_name = 'helic3_cargas'

  TIPOS = %w[facturas].freeze
  MODOS = %w[sobrescribir anexar].freeze
  ESTADOS = %w[procesando completado fallido].freeze

  belongs_to :account
  belongs_to :usuario, class_name: 'User', optional: true
  has_many :facturas, class_name: 'Helic3::FacturaVenta', inverse_of: :carga, dependent: :restrict_with_error

  # revision de Jhan (PR #140): el archivo se procesa en un job, fuera de la
  # peticion -- necesita sobrevivir mas alla del tempfile del upload, que Rails
  # borra apenas termina la peticion.
  has_one_attached :archivo

  validates :tipo, inclusion: { in: TIPOS }
  validates :modo, inclusion: { in: MODOS }
  validates :estado, inclusion: { in: ESTADOS }
  validates :nombre_archivo, presence: true
end
