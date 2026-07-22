# Vector search backed by the embedding column on knowledge_chunks
# (pgvector + neighbor gem). Since embeddings are always persisted on the
# chunks, switching to this adapter requires no re-ingestion.
class Knowledge::VectorStore::Pgvector < Knowledge::VectorStore::Base
  def upsert_chunks(chunks_with_vectors)
    # embeddings are already stored on the chunk records during ingestion
    chunks_with_vectors
  end

  def search(vector, account_id:, limit: 5)
    Knowledge::Chunk.where(account_id: account_id)
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
