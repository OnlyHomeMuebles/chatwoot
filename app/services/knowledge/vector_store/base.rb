class Knowledge::VectorStore::Base
  # chunks_with_vectors: array of [Knowledge::Chunk, vector] pairs
  def upsert_chunks(_chunks_with_vectors)
    raise NotImplementedError
  end

  def search(_vector, account_id:, limit: 5)
    raise NotImplementedError
  end

  def delete_document(_document)
    raise NotImplementedError
  end
end
