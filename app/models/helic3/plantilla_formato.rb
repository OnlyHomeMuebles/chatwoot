# frozen_string_literal: true

# FMT-02: una version de plantilla de un formato. Guarda el .docx original (como lo
# subio Karen) y su conversion a .fodt (lo que se rellena). Estados: borrador ->
# activa -> retirada. Por formato hay varias versiones pero solo una activa (lo
# garantiza el indice parcial de la migracion). Una activa/retirada no se borra:
# los documentos generados la referencian.
class Helic3::PlantillaFormato < ApplicationRecord
  self.table_name = 'helic3_plantillas_formato'

  ESTADOS = %w[borrador activa retirada].freeze

  belongs_to :account
  belongs_to :formato, class_name: 'Helic3::Catalogo::Formato'
  # subio/activo: se guarda quien, pero si el usuario se borra la FK queda en null
  # (on_delete: :nullify en la migracion) y ademas guardamos el nombre como instantanea.
  belongs_to :subido_por, class_name: 'User', optional: true
  belongs_to :activada_por, class_name: 'User', optional: true

  # Active Storage: el .docx tal cual, y el .fodt (OpenDocument plano) que se llena.
  has_one_attached :original
  has_one_attached :fodt

  validates :estado, inclusion: { in: ESTADOS }
  validates :version, numericality: { only_integer: true, greater_than: 0 }

  scope :activa, -> { where(estado: 'activa') }

  before_destroy :solo_borrador_se_borra

  private

  # Solo un borrador se puede borrar; throw(:abort) cancela el destroy (devuelve false).
  def solo_borrador_se_borra
    return if estado == 'borrador'

    errors.add(:base, 'una plantilla activa o retirada no se puede borrar')
    throw(:abort)
  end
end
