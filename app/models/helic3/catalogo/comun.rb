# Comportamiento comun de todo catalogo de clasificacion (criterios 2 y 3 de
# CAT-01): pertenece a una cuenta, exige nombre y codigo, el codigo es unico
# por cuenta, y un valor desactivado deja de ofrecerse sin borrarse jamas
# (los casos que ya lo usan lo siguen resolviendo por id).
module Helic3::Catalogo::Comun
  extend ActiveSupport::Concern

  included do
    belongs_to :account

    validates :nombre, presence: true
    validates :codigo, presence: true, uniqueness: { scope: :account_id }
    validates :posicion, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :activos, -> { where(activo: true).order(:posicion) }
  end
end
