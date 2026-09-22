# EVI-01: el archivo documental del expediente. Nace con dos procedencias --
# un adjunto de la conversacion (se referencia via `attachment`, nunca se
# copia el archivo) o un archivo propio del modulo (`archivo`, formato
# generado o carga manual). El modelo solo persiste y valida coherencia;
# quien decide CUANDO nace un documento es el servicio de dominio
# (Helic3::Casos::VincularEvidencias), igual que Helic3::Evento con sus
# servicios.
# == Schema Information
#
# Table name: helic3_documentos
#
#  id                :bigint           not null, primary key
#  clase             :string           not null
#  descripcion       :text
#  metadata          :jsonb            not null
#  ocurrido_at       :datetime         not null
#  origen            :string           not null
#  remitente_nombre  :string
#  titulo            :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  attachment_id     :integer
#  garantia_id       :bigint
#  message_id        :integer
#  remitente_user_id :bigint
#  ticket_id         :bigint           not null
#
# Indexes
#
#  idx_h3_documentos_account                  (account_id)
#  idx_h3_documentos_attachment               (attachment_id)
#  idx_h3_documentos_garantia                 (garantia_id)
#  idx_h3_documentos_message                  (message_id)
#  idx_h3_documentos_remitente_user           (remitente_user_id)
#  idx_h3_documentos_ticket                   (ticket_id)
#  idx_h3_documentos_ticket_attachment_unico  (ticket_id,attachment_id) UNIQUE WHERE (attachment_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (attachment_id => attachments.id)
#  fk_rails_...  (garantia_id => helic3_garantias.id)
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (remitente_user_id => users.id)
#  fk_rails_...  (ticket_id => helic3_tickets.id)
#
class Helic3::Documento < ApplicationRecord
  self.table_name = 'helic3_documentos'

  # listas cerradas: son conceptos del dominio, no valores que Karen edite
  # desde catalogos.
  CLASES = %w[evidencia formato].freeze
  ORIGENES = %w[cliente operador agente sistema].freeze

  belongs_to :account
  belongs_to :ticket, class_name: 'Helic3::Ticket', inverse_of: :documentos
  belongs_to :garantia, class_name: 'Helic3::Garantia', optional: true
  belongs_to :attachment, optional: true
  belongs_to :message, optional: true
  belongs_to :remitente_user, class_name: 'User', optional: true

  has_one_attached :archivo

  validates :clase, inclusion: { in: CLASES }
  validates :origen, inclusion: { in: ORIGENES }
  validate :validate_una_procedencia
  validate :validate_ticket_belongs_to_account
  validate :validate_attachment_belongs_to_account
  validate :validate_archivo

  # Resuelve la URL de descarga indistintamente contra el adjunto referenciado
  # o el archivo propio: el consumidor (API, frontend) no necesita saber de
  # cual de las dos procedencias viene.
  def url
    return attachment.download_url if attachment_con_archivo?

    return nil unless archivo.attached?

    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    archivo.blob.url
  end

  def tipo_archivo
    return attachment.file.content_type if attachment_con_archivo?
    return nil unless archivo.attached?

    archivo.content_type
  end

  private

  # El attachment referenciado puede existir (FK valida) sin traer un archivo
  # real adjunto -- p. ej. un mensaje de ubicacion o de contacto no tiene blob
  # (ver Attachment#with_attached_file?). Sin esta guarda, tipo_archivo/url
  # revientan con un attachment de ese tipo.
  def attachment_con_archivo?
    attachment.present? && attachment.file.attached?
  end

  # exactamente una procedencia: o trae attachment, o trae archivo adjunto.
  # Nunca las dos, nunca ninguna.
  def validate_una_procedencia
    return if attachment.present? ^ archivo.attached?

    errors.add(:base, 'debe tener exactamente una procedencia: un adjunto de la conversacion o un archivo propio')
  end

  def validate_ticket_belongs_to_account
    return if ticket.nil? || ticket.account_id == account_id

    errors.add(:ticket, 'must belong to the same account')
  end

  def validate_attachment_belongs_to_account
    return if attachment.nil? || attachment.account_id == account_id

    errors.add(:attachment, 'must belong to the same account')
  end

  # Procedencia B (carga manual, EVI-03): a diferencia del attachment
  # referenciado, que ya paso por las validaciones de Attachment cuando nacio,
  # este archivo nunca las vio. Expediente con valor probatorio ante la SIC:
  # no puede aceptar un ejecutable ni un archivo sin limite de peso. Mismo
  # limite y misma lista de tipos que Attachment#acceptable_file.
  def validate_archivo
    return unless archivo.attached?

    limite_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limite_mb = 40 if limite_mb <= 0
    errors.add(:archivo, 'size is too big') if archivo.byte_size > limite_mb.megabytes

    tipo = archivo.content_type.to_s
    return if tipo.start_with?('image/', 'video/', 'audio/') || Attachment::ACCEPTABLE_FILE_TYPES.include?(tipo)

    errors.add(:archivo, 'content type not supported')
  end
end
