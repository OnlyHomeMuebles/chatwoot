# frozen_string_literal: true

# Retira la tabla del RAG local basado en Ollama (OnlyHome::KnowledgeChunk), superado por el sistema
# de conocimiento unificado (Knowledge::* con la tool search_knowledge_base). Ver la migración
# 20260818000000 que la creó.
class DropOnlyHomeKnowledgeChunks < ActiveRecord::Migration[7.1]
  def up
    drop_table :only_home_knowledge_chunks, if_exists: true
  end

  def down
    create_table :only_home_knowledge_chunks do |t|
      t.string :category, null: false
      t.string :source
      t.text :content, null: false
      t.vector :embedding, limit: 768
      t.timestamps
    end
  end
end
