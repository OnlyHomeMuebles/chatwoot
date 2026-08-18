# frozen_string_literal: true

require 'httparty'

# Genera embeddings con un modelo OPEN SOURCE local vía Ollama (por defecto nomic-embed-text, 768
# dimensiones). Sin API propietaria ni cuota. Se usa para indexar el conocimiento y para embeber la
# pregunta del cliente en el RAG.
module OnlyHome::Embeddings
  module_function

  def embed(text)
    base = ENV.fetch('OLLAMA_API_BASE', 'http://localhost:11434/v1').sub(%r{/v1/?$}, '')
    response = HTTParty.post(
      "#{base}/api/embeddings",
      headers: { 'Content-Type' => 'application/json' },
      body: { model: ENV.fetch('ONLY_HOME_EMBEDDING_MODEL', 'nomic-embed-text'), prompt: text.to_s }.to_json,
      timeout: 30
    )
    raise "Ollama embeddings respondió #{response.code}: #{response.body}" unless response.success?

    response.parsed_response['embedding']
  end
end
