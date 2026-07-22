# == Schema Information
#
# Table name: knowledge_documents
#
#  id                  :bigint           not null, primary key
#  content             :text
#  content_fingerprint :string
#  external_link       :string
#  last_ingested_at    :datetime
#  metadata            :jsonb
#  name                :string           not null
#  source_type         :integer          default("url"), not null
#  status              :integer          default("pending"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_knowledge_documents_on_account_id_and_external_link  (account_id,external_link) UNIQUE
#  index_knowledge_documents_on_status                        (status)
#
class Knowledge::Document < ApplicationRecord
  self.table_name = 'knowledge_documents'

  belongs_to :account
  has_many :chunks, class_name: 'Knowledge::Chunk',
                    dependent: :destroy, inverse_of: :document

  enum :source_type, { url: 0, dataset: 1, file: 2 }, prefix: :source
  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :name, presence: true
  validates :external_link, uniqueness: { scope: :account_id }, allow_nil: true
  # knowledge sources are long by nature; override the global 20k text cap
  # from ApplicationRecord with an explicit (still bounded) limit
  validates :content, length: { maximum: 5_000_000 }

  scope :ordered, -> { order(created_at: :desc) }
end
