# frozen_string_literal: true

# Tabla de fragmentos de conocimiento de Only Home para el RAG del agente OSS. Cada fila es un
# trozo semántico del catálogo/tiendas/políticas con su embedding local (nomic-embed-text, 768 dim),
# para recuperar por similitud vectorial solo lo relevante a cada pregunta.
class CreateOnlyHomeKnowledgeChunks < ActiveRecord::Migration[7.1]
  def change
    create_table :only_home_knowledge_chunks do |t|
      t.string :category, null: false
      t.string :source
      t.text :content, null: false
      t.vector :embedding, limit: 768
      t.timestamps
    end
  end
end
