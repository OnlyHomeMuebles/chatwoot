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
# == Schema Information
#
# Table name: helic3_agentes
#
#  id               :bigint           not null, primary key
#  activo           :boolean          default(TRUE), not null
#  codigo           :string           not null
#  confianza_minima :integer
#  criterio_ruteo   :text
#  descripcion      :text
#  es_sistema       :boolean          default(FALSE), not null
#  handoff_reglas   :jsonb            not null
#  herramientas     :jsonb            not null
#  horario          :string
#  max_respuestas   :integer
#  mensaje_handoff  :text
#  modelo           :string
#  nombre           :string           not null
#  politicas        :jsonb            not null
#  politicas_texto  :text
#  prompt           :text
#  tono             :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  creado_por_id    :bigint
#  team_id          :bigint
#
# Indexes
#
#  idx_h3ag_account         (account_id)
#  idx_h3ag_account_activo  (account_id,activo)
#  idx_h3ag_account_codigo  (account_id,codigo) UNIQUE
#  idx_h3ag_creado_por      (creado_por_id)
#  idx_h3ag_team            (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (creado_por_id => users.id) ON DELETE => nullify
#  fk_rails_...  (team_id => teams.id) ON DELETE => nullify
#
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
  # H3A-09 (revision de Jhan): un agente sin prompt no tiene identidad, y en el
  # triage un prompt nil rompia el armado del directorio dinamico. El runner ademas
  # lo lee con .to_s como red de seguridad para las filas que ya existan.
  validates :prompt, presence: true
  # solo puede haber un agente de sistema (el triage) por cuenta: es el hub de ruteo
  validates :es_sistema, uniqueness: { scope: :account_id }, if: :es_sistema?
  validates :confianza_minima,
            numericality: { only_integer: true, greater_than_or_equal_to: 50, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :max_respuestas,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 30 },
            allow_nil: true

  before_validation :filtrar_herramientas
  before_destroy :proteger_agente_de_sistema
  # H3A-06: guardar/pausar/borrar un agente invalida la cache de config de la cuenta,
  # para que el cambio se refleje en el siguiente mensaje sin reiniciar el proceso.
  after_commit :invalidar_config_cache

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

  def invalidar_config_cache
    Helic3::Agents::ConfigCache.invalidar(account_id)
  end

  # el triage (u otro es_sistema) no se puede eliminar; H3A-05 tambien lo bloquea
  # en el controlador, pero el guard vive aqui para que aplique desde cualquier via.
  def proteger_agente_de_sistema
    return unless es_sistema?

    errors.add(:base, 'un agente de sistema no se puede eliminar')
    throw(:abort)
  end
end
