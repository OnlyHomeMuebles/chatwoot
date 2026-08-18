# frozen_string_literal: true

# Fragmento de conocimiento de Only Home con su embedding local, para el RAG del agente. Cada chunk
# es un trozo semántico (una tienda, una línea de producto, un combo, una política, una FAQ) que se
# recupera por similitud vectorial. Espejo OSS de Captain::AssistantResponse (pgvector + neighbor).
class OnlyHome::KnowledgeChunk < ApplicationRecord
  self.table_name = 'only_home_knowledge_chunks'

  has_neighbors :embedding, normalize: true

  validates :category, :content, presence: true

  # Recupera los chunks más parecidos a un embedding de consulta (distancia coseno).
  def self.search(query_embedding, limit: 5)
    nearest_neighbors(:embedding, query_embedding, distance: 'cosine').limit(limit)
  end
end
