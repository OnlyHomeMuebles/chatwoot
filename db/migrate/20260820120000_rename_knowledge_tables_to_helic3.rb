# Convencion Helic3 (decision del 19/08): las tablas del modulo propio llevan
# prefijo helic3_. Renombra las tablas del RAG conservando datos e indices.
# Con guardas por si el entorno ya renombro manualmente (idempotente).
class RenameKnowledgeTablesToHelic3 < ActiveRecord::Migration[7.2]
  # renombres de indice que no puede resolver rename_table:
  # - el del unique de documents quedaria en 65 caracteres (limite de Postgres: 63)
  # - el del embedding tiene nombre manual, no el generado por Rails
  INDICES = {
    helic3_knowledge_documents: {
      'index_knowledge_documents_on_account_id_and_external_link' => 'idx_h3_knowledge_documents_account_external_link',
      'index_knowledge_documents_on_status' => 'index_helic3_knowledge_documents_on_status'
    },
    helic3_knowledge_chunks: {
      'idx_knowledge_chunks_on_embedding' => 'idx_helic3_knowledge_chunks_on_embedding',
      'index_knowledge_chunks_on_account_id' => 'index_helic3_knowledge_chunks_on_account_id',
      'index_knowledge_chunks_on_document_id' => 'index_helic3_knowledge_chunks_on_document_id'
    }
  }.freeze

  def up
    rename_with_indexes(:knowledge_documents, :helic3_knowledge_documents)
    rename_with_indexes(:knowledge_chunks, :helic3_knowledge_chunks)
  end

  def down
    rename_with_indexes(:helic3_knowledge_documents, :knowledge_documents, reverse: true)
    rename_with_indexes(:helic3_knowledge_chunks, :knowledge_chunks, reverse: true)
  end

  private

  def rename_with_indexes(old_name, new_name, reverse: false)
    return unless table_exists?(old_name)

    mapping = index_mapping(old_name, new_name, reverse)
    # el indice largo se renombra ANTES: si rename_table intentara generarle
    # nombre nuevo, superaria los 63 caracteres y fallaria
    rename_indexes(old_name, mapping)
    rename_table old_name, new_name
    # por si rename_table dejo algun indice con nombre viejo
    rename_indexes(new_name, mapping)
  end

  def index_mapping(old_name, new_name, reverse)
    mapping = INDICES.fetch(reverse ? old_name : new_name)
    reverse ? mapping.invert : mapping
  end

  def rename_indexes(table, mapping)
    mapping.each do |viejo, nuevo|
      rename_index table, viejo, nuevo if index_name_exists?(table, viejo)
    end
  end
end
