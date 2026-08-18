# frozen_string_literal: true

# Recupera del índice los fragmentos de conocimiento más relevantes para la pregunta del cliente,
# por similitud vectorial (coseno). Es el paso "retrieval" del RAG: en vez de mandarle TODO el
# catálogo al modelo, le damos solo estos pocos fragmentos → respuestas precisas con un modelo local
# pequeño. Espejo OSS de Captain::AssistantResponse.search.
module OnlyHome::KnowledgeRetriever
  module_function

  # Devuelve el texto de los `limit` chunks más parecidos, listo para inyectar en el prompt.
  def context_for(query, limit: 5)
    chunks(query, limit: limit).map(&:content).join("\n")
  end

  def chunks(query, limit: 5)
    embedding = OnlyHome::Embeddings.embed(query)
    OnlyHome::KnowledgeChunk.search(embedding, limit: limit).to_a
  end
end
