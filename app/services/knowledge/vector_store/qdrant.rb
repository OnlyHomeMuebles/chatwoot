class Knowledge::VectorStore::Qdrant < Knowledge::VectorStore::Base
  COLLECTION = 'knowledge_chunks'.freeze
  VECTOR_SIZE = 1536

  def initialize(url: nil)
    super()
    @url = url || ENV.fetch('QDRANT_URL', 'http://qdrant:6333')
  end

  def upsert_chunks(chunks_with_vectors)
    ensure_collection

    points = chunks_with_vectors.map do |chunk, vector|
      {
        id: chunk.id,
        vector: vector,
        payload: { account_id: chunk.account_id, document_id: chunk.document_id, content: chunk.content }
      }
    end
    request(:put, "/collections/#{COLLECTION}/points?wait=true", { points: points })
  end

  def search(vector, account_id:, limit: 5)
    ensure_collection

    response = request(:post, "/collections/#{COLLECTION}/points/search", {
                         vector: vector,
                         limit: limit,
                         with_payload: true,
                         filter: { must: [{ key: 'account_id', match: { value: account_id } }] }
                       })

    (response['result'] || []).map do |point|
      {
        chunk_id: point['id'],
        score: point['score'],
        content: point.dig('payload', 'content'),
        document_id: point.dig('payload', 'document_id')
      }
    end
  end

  def delete_document(document)
    ensure_collection
    request(:post, "/collections/#{COLLECTION}/points/delete?wait=true", {
              filter: { must: [{ key: 'document_id', match: { value: document.id } }] }
            })
  end

  private

  def ensure_collection
    return if @collection_ready

    if connection.get("/collections/#{COLLECTION}").status == 404
      request(:put, "/collections/#{COLLECTION}", { vectors: { size: VECTOR_SIZE, distance: 'Cosine' } })
      create_payload_indexes
    end
    @collection_ready = true
  end

  def create_payload_indexes
    %w[account_id document_id].each do |field|
      request(:put, "/collections/#{COLLECTION}/index", { field_name: field, field_schema: 'integer' })
    end
  end

  def connection
    @connection ||= Faraday.new(url: @url) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
    end
  end

  def request(method, path, body = nil)
    response = connection.public_send(method, path, body)
    raise Knowledge::VectorStore::Error, "Qdrant #{method.upcase} #{path} failed (#{response.status}): #{response.body}" unless response.success?

    response.body
  end
end
