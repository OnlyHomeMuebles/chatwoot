class CreateKnowledgeBase < ActiveRecord::Migration[7.1]
  def change
    create_documents
    create_chunks
  end

  private

  def create_documents
    create_table :knowledge_documents do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.integer :source_type, default: 0, null: false
      t.string :external_link
      t.text :content
      t.string :content_fingerprint
      t.integer :status, default: 0, null: false
      t.jsonb :metadata, default: {}
      t.datetime :last_ingested_at

      t.timestamps
    end

    add_index :knowledge_documents, [:account_id, :external_link], unique: true
    add_index :knowledge_documents, :status
  end

  def create_chunks
    create_table :knowledge_chunks do |t|
      t.bigint :account_id, null: false
      t.bigint :document_id, null: false
      t.text :content, null: false
      t.integer :position, default: 0, null: false
      t.vector :embedding, limit: 1536
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :knowledge_chunks, :account_id
    add_index :knowledge_chunks, :document_id
    add_index :knowledge_chunks, :embedding, using: :ivfflat, opclass: :vector_cosine_ops,
                                             name: 'idx_knowledge_chunks_on_embedding'
  end
end
