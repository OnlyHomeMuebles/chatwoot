# Parametros de operacion del modulo (CAT-02, frente B): el presupuesto
# global de la garantia (30 dias habiles), el plazo de la PQR, el umbral de
# confianza del agente... Valores que gobiernan la operacion pero no
# pertenecen a ningun catalogo puntual. La unidad dice como interpretar el
# valor (dias_habiles, dias, meses, porcentaje, cantidad, booleano).
# == Schema Information
#
# Table name: helic3_catalogo_parametros
#
#  id         :bigint           not null, primary key
#  clave      :string           not null
#  unidad     :string           not null
#  valor      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  idx_h3cat_parametros_account        (account_id)
#  idx_h3cat_parametros_account_clave  (account_id,clave) UNIQUE
#
class Helic3::Catalogo::Parametro < ApplicationRecord
  # texto entro con GAR-01: el prefijo del radicado de garantia es una cadena
  UNIDADES = %w[dias_habiles dias meses porcentaje cantidad booleano texto].freeze

  belongs_to :account

  validates :clave, presence: true, uniqueness: { scope: :account_id }
  validates :valor, presence: true
  validates :unidad, presence: true, inclusion: { in: UNIDADES }

  # el valor se guarda como texto; estos lectores lo interpretan segun la unidad
  def valor_entero
    Integer(valor, exception: false)
  end

  def valor_booleano
    ActiveModel::Type::Boolean.new.cast(valor)
  end
end
