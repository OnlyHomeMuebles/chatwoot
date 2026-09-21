# frozen_string_literal: true

# H3A-02: un agente del bot como dato administrable. Reemplaza a las clases
# quemadas (TriageAgent, FaqAgent, ...) que hoy arma RunnerService a mano.
# El runner (H3A-08) construira cada agente leyendo estas filas.
#
# Reglas del dominio:
# - nombre obligatorio.
# - criterio_ruteo obligatorio salvo en el agente de sistema (el triage, que no
#   se enruta a si mismo).
# - confianza_minima 50..100 y max_respuestas 1..30 (ambos opcionales).
# - herramientas se filtran contra el catalogo fijo (H3A-03): una clave
#   desconocida no se guarda.
class Helic3::Agente < ApplicationRecord
  self.table_name = 'helic3_agentes'

  belongs_to :account
  belongs_to :team, optional: true
  belongs_to :creado_por, class_name: 'User', optional: true

  has_many :agente_bandejas, class_name: 'Helic3::AgenteBandeja',
                             inverse_of: :agente, dependent: :destroy
  has_many :inboxes, through: :agente_bandejas

  validates :codigo, presence: true, uniqueness: { scope: :account_id }
  validates :nombre, presence: true
  validates :criterio_ruteo, presence: true, unless: :es_sistema?
  validates :confianza_minima,
            numericality: { only_integer: true, greater_than_or_equal_to: 50, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :max_respuestas,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 30 },
            allow_nil: true

  before_validation :filtrar_herramientas
  before_destroy :proteger_agente_de_sistema

  scope :activos, -> { where(activo: true) }

  # agentes activos de la cuenta del inbox que atienden ESE inbox. Es lo que el
  # runner (H3A-08) usa para armar la orquesta de cada mensaje.
  def self.activos_para(inbox)
    joins(:agente_bandejas)
      .where(account_id: inbox.account_id, activo: true)
      .where(helic3_agentes_bandejas: { inbox_id: inbox.id })
  end

  private

  # solo sobreviven las claves del catalogo (H3A-03), sin duplicados y
  # conservando el orden en que las eligio el admin.
  def filtrar_herramientas
    self.herramientas = Array(herramientas).map(&:to_s).uniq & Helic3::Agents::CatalogoHerramientas::CLAVES
  end

  # el triage (u otro es_sistema) no se puede eliminar; H3A-05 tambien lo bloquea
  # en el controlador, pero el guard vive aqui para que aplique desde cualquier via.
  def proteger_agente_de_sistema
    return unless es_sistema?

    errors.add(:base, 'un agente de sistema no se puede eliminar')
    throw(:abort)
  end
end
