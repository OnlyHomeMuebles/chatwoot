# Semantic search over the account's knowledge base: embeds the query and
# asks the configured vector store for the nearest chunks.
class Knowledge::SearchService
  def initialize(account)
    @account = account
  end

  def search(query, limit: 5)
    return [] if query.blank?

    vector = Knowledge::EmbeddingService.new.embed(query)
    Knowledge::VectorStore.adapter.search(vector, account_id: @account.id, limit: limit)
  end
end
