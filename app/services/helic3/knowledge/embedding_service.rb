# Genera embeddings con la llave de OpenAI de Super Admin
# (Helic3::Agents::LlmRuntime, CFG-01).
class Helic3::Knowledge::EmbeddingService
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
    raise EmbeddingError, Helic3::Agents::LlmRuntime::SIN_LLAVE if api_key.blank?

    @context ||= RubyLLM.context do |config|
      config.openai_api_key = api_key
      config.openai_api_base = Helic3::Agents::LlmRuntime.api_base
    end
  end

  def api_key
    @api_key ||= Helic3::Agents::LlmRuntime.api_key
  end
end
