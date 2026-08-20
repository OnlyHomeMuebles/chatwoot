# == Schema Information
#
# Table name: helic3_knowledge_chunks
#
#  id          :bigint           not null, primary key
#  content     :text             not null
#  embedding   :vector(1536)
#  metadata    :jsonb
#  position    :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  document_id :bigint           not null
#
# Indexes
#
#  idx_helic3_knowledge_chunks_on_embedding      (embedding) USING ivfflat
#  index_helic3_knowledge_chunks_on_account_id   (account_id)
#  index_helic3_knowledge_chunks_on_document_id  (document_id)
#
class Helic3::Knowledge::Chunk < ApplicationRecord
  belongs_to :account
  belongs_to :document, class_name: 'Helic3::Knowledge::Document', inverse_of: :chunks

  # embeddings live here as the source of truth: search runs directly on
  # this column (pgvector + neighbor), and any future external backend
  # could rebuild itself from these rows without re-ingesting
  has_neighbors :embedding, normalize: true

  validates :content, presence: true
end
