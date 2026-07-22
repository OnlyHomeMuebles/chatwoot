# Abstraction over the vector storage backend. The backend is chosen via
# the KNOWLEDGE_VECTOR_STORE env var so it can be swapped without touching
# the ingestion or search code (Qdrant today, pgvector when the company
# database is available).
module Knowledge::VectorStore
  class Error < StandardError; end

  def self.adapter
    case ENV.fetch('KNOWLEDGE_VECTOR_STORE', 'qdrant')
    when 'pgvector'
      Knowledge::VectorStore::Pgvector.new
    else
      Knowledge::VectorStore::Qdrant.new
    end
  end
end
