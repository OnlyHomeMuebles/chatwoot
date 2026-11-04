# frozen_string_literal: true

# COR-01: el correo que recibe el cliente cuando un producto de la garantia
# cambia de proceso, o cuando se cierra el caso (disparador = 'cierre_caso',
# sin proceso). El cuerpo es texto plano con dos marcas: **negrita** y una
# linea en blanco entre parrafos -- nunca HTML, asi Karen no puede romper el
# correo ni inyectar nada (COR-02 lo escapa igual antes de renderizar).
# == Schema Information
#
# Table name: helic3_plantillas_correo
#
#  id                  :bigint           not null, primary key
#  activo              :boolean          default(TRUE), not null
#  asunto              :string           not null
#  cuerpo              :text             not null
#  disparador          :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  proceso_garantia_id :bigint
#
# Indexes
#
#  idx_h3_plantilla_correo_account        (account_id)
#  idx_h3_plantilla_correo_cierre_unico   (account_id) UNIQUE WHERE ((disparador)::text = 'cierre_caso'::text)
#  idx_h3_plantilla_correo_proceso_unico  (account_id,proceso_garantia_id) UNIQUE WHERE ((disparador)::text = 'proceso_garantia'::text)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (proceso_garantia_id => helic3_catalogo_procesos_garantia.id)
#
class Helic3::PlantillaCorreo < ApplicationRecord
  self.table_name = 'helic3_plantillas_correo'

  DISPARADORES = %w[proceso_garantia cierre_caso].freeze
  MARCADOR = /\{\{(\w+)\}\}/

  belongs_to :account
  belongs_to :proceso_garantia, class_name: 'Helic3::Catalogo::ProcesoGarantia', optional: true

  validates :disparador, inclusion: { in: DISPARADORES }
  validates :asunto, :cuerpo, presence: true
  validate :proceso_segun_disparador
  validate :marcadores_conocidos
  validate :validate_proceso_belongs_to_account

  scope :activas, -> { where(activo: true) }

  private

  def validate_proceso_belongs_to_account
    return if proceso_garantia.nil? || proceso_garantia.account_id == account_id

    errors.add(:proceso_garantia, 'must belong to the same account')
  end

  def proceso_segun_disparador
    if disparador == 'proceso_garantia' && proceso_garantia_id.blank?
      errors.add(:proceso_garantia, 'es obligatorio para una plantilla de proceso_garantia')
    elsif disparador == 'cierre_caso' && proceso_garantia_id.present?
      errors.add(:proceso_garantia, 'no aplica para una plantilla de cierre_caso')
    end
  end

  # Un {{MARCADOR}} que no exista en el diccionario (p. ej. un error de tipeo
  # de Karen, {{CLIETNE}}) es un error de validacion, no un correo roto en
  # produccion.
  def marcadores_conocidos
    desconocidos = marcadores_usados.reject { |marcador| Helic3::Formatos::Marcadores.conocido?(marcador) }
    return if desconocidos.empty?

    errors.add(:base, "marcador desconocido: #{desconocidos.join(', ')}")
  end

  def marcadores_usados
    "#{asunto} #{cuerpo}".scan(MARCADOR).flatten.uniq
  end
end
