# Comportamiento comun de todo catalogo de clasificacion (criterios 2 y 3 de
# CAT-01): pertenece a una cuenta, exige nombre y codigo, el codigo es unico
# por cuenta, y un valor desactivado deja de ofrecerse sin borrarse jamas
# (los casos que ya lo usan lo siguen resolviendo por id).
module Helic3::Catalogo::Comun
  extend ActiveSupport::Concern

  included do
    belongs_to :account

    # El codigo y el nombre se guardan SIN espacios de sobra: un "nueva " invisible
    # (cargado por Excel/consola/pantalla) hacia que find_by!(codigo: 'nueva') de
    # Radicar fallara y toda PQR nueva respondiera 404. normalizes corre antes de
    # validar, asi que "nueva " entra como "nueva".
    normalizes :codigo, with: ->(valor) { valor.to_s.strip }
    normalizes :nombre, with: ->(valor) { valor.to_s.strip }

    validates :nombre, presence: true
    validates :codigo, presence: true, uniqueness: { scope: :account_id },
                       format: {
                         with: /\A[a-z0-9_]+\z/,
                         message: 'solo admite minusculas, numeros y guion bajo'
                       }
    validates :posicion, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :activos, -> { where(activo: true).order(:posicion) }
  end
end
