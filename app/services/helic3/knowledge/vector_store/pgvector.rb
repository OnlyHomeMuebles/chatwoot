# Vector search backed by the embedding column on helic3_knowledge_chunks
# (pgvector + neighbor gem). Since embeddings are always persisted on the
# chunks, switching to this adapter requires no re-ingestion.
class Helic3::Knowledge::VectorStore::Pgvector < Helic3::Knowledge::VectorStore::Base
  def upsert_chunks(chunks_with_vectors)
    # embeddings are already stored on the chunk records during ingestion
    chunks_with_vectors
  end

  def search(vector, account_id:, limit: 5)
    # ivfflat sondea por defecto UN solo cluster (probes=1) y su recall es
    # pobre; con 10 sondas la busqueda es casi exacta a este tamano de base.
    # Nota operativa: tras una carga masiva hay que re-entrenar el indice
    # (REINDEX INDEX idx_helic3_knowledge_chunks_on_embedding) — ivfflat aprende de
    # los datos presentes al construirse.
    Helic3::Knowledge::Chunk.connection.execute('SET ivfflat.probes = 10')
    Helic3::Knowledge::Chunk.where(account_id: account_id)
                            .nearest_neighbors(:embedding, vector, distance: 'cosine')
                            .limit(limit)
                            .map do |chunk|
      {
        chunk_id: chunk.id,
        score: 1 - chunk.neighbor_distance,
        content: chunk.content,
        document_id: chunk.document_id
      }
    end
  end

  def delete_document(document)
    # chunk rows (and their embeddings) are removed with the document
    document
  end
end
