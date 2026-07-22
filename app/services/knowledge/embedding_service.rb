# Generates embeddings via RubyLLM using the OPENAI_API_KEY env var
# (falls back to the Captain installation config key when present).
class Knowledge::EmbeddingService
  DEFAULT_MODEL = 'text-embedding-3-small'.freeze

  class EmbeddingError < StandardError; end

  def initialize(model: nil)
    Llm::Config.initialize!
    @model = model || ENV.fetch('KNOWLEDGE_EMBEDDING_MODEL', DEFAULT_MODEL)
  end

  def embed(content)
    return [] if content.blank?

    context.embed(content, model: @model).vectors
  rescue RubyLLM::Error => e
    raise EmbeddingError, "Failed to generate embedding: #{e.message}"
  end

  def embed_batch(contents)
    contents = contents.reject(&:blank?)
    return [] if contents.empty?

    context.embed(contents, model: @model).vectors
  rescue RubyLLM::Error => e
    raise EmbeddingError, "Failed to generate embeddings: #{e.message}"
  end

  private

  def context
    @context ||= RubyLLM.context do |config|
      config.openai_api_key = api_key if api_key.present?
    end
  end

  def api_key
    ENV['OPENAI_API_KEY'].presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end
end
