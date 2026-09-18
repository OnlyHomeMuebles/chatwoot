# frozen_string_literal: true

# AGT-04: sacar un CSV de db/knowledge_seeds deja de re-ingestarlo, pero el Document y sus
# chunks YA ingestados siguen en la base y search_knowledge_base los sigue devolviendo. Esta
# purga (idempotente y reproducible) borra los documentos dataset "de semilla" que ya no
# tienen un CSV vigente, para que el corpus del RAG refleje exactamente lo que hay en la
# carpeta de semillas.
#
# Protege los datasets que NO vienen de un CSV de semilla: el catalogo (ingest_catalog) y las
# conversaciones aprobadas de AGT-05 (conversacion_<display_id>).
class Helic3::Knowledge::DatasetPurge
  PROTEGIDOS = ['catalogo_helic3'].freeze
  PREFIJO_CONVERSACION = 'conversacion_'

  def initialize(account, nombres_vigentes)
    @account = account
    @nombres_vigentes = Array(nombres_vigentes)
  end

  # @return [Array<String>] nombres de los documentos purgados (para trazar en el rake/log)
  def call
    huerfanos.map do |document|
      Helic3::Knowledge::VectorStore.adapter.delete_document(document)
      document.destroy!
      document.name
    end
  end

  private

  def huerfanos
    Helic3::Knowledge::Document
      .where(account: @account, source_type: :dataset)
      .where.not(name: @nombres_vigentes + PROTEGIDOS)
      .reject { |document| document.name.to_s.start_with?(PREFIJO_CONVERSACION) }
  end
end
