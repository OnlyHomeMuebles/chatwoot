# Abstraction over the vector storage backend, chosen via the
# KNOWLEDGE_VECTOR_STORE env var so it can be swapped without touching the
# ingestion or search code. pgvector (the app's own Postgres) is the only
# backend today; the seam stays for a future external store if scale demands it.
module Knowledge::VectorStore
  class Error < StandardError; end

  def self.adapter
    backend = ENV.fetch('KNOWLEDGE_VECTOR_STORE', 'pgvector')
    raise Error, "Backend vectorial desconocido: #{backend}" unless backend == 'pgvector'

    Knowledge::VectorStore::Pgvector.new
  end
end
