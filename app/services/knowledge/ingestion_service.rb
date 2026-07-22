# Turns a Knowledge::Document's content into embedded chunks stored in the
# configured vector store. Re-running is cheap: a content fingerprint
# (borrowed from Captain's sync design) skips documents that didn't change,
# which makes ingestion incremental and reproducible.
class Knowledge::IngestionService
  BATCH_SIZE = 50

  def initialize(document)
    @document = document
  end

  def perform
    raise ArgumentError, 'document has no content' if @document.content.blank?

    fingerprint = compute_fingerprint
    return :unchanged if fingerprint == @document.content_fingerprint && @document.ready?

    @document.update!(status: :processing)
    reingest_chunks

    @document.update!(status: :ready, content_fingerprint: fingerprint, last_ingested_at: Time.current)
    :ingested
  rescue StandardError => e
    @document.update!(status: :failed, metadata: @document.metadata.merge('last_error' => e.message))
    raise
  end

  private

  def reingest_chunks
    store = Knowledge::VectorStore.adapter
    store.delete_document(@document)
    @document.chunks.destroy_all

    texts = Knowledge::ChunkingService.new(@document.content).chunks
    embedder = Knowledge::EmbeddingService.new

    texts.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      vectors = embedder.embed_batch(batch)
      store.upsert_chunks(persist_chunks(batch, vectors, batch_index))
    end
  end

  def persist_chunks(batch, vectors, batch_index)
    batch.each_with_index.map do |text, index|
      chunk = @document.chunks.create!(
        account_id: @document.account_id,
        content: text,
        position: (batch_index * BATCH_SIZE) + index,
        embedding: vectors[index]
      )
      [chunk, vectors[index]]
    end
  end

  def compute_fingerprint
    Digest::SHA256.hexdigest(@document.content.gsub(/\s+/, ' ').strip)
  end
end
