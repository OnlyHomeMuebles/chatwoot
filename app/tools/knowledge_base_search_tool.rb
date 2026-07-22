# Tool de la gema ai-agents que expone la base de conocimiento de Only Home
# a los agentes LLM. Sin estado propio: todo el contexto de ejecucion llega
# via tool_context (thread-safe segun el contrato de Agents::Tool).
class KnowledgeBaseSearchTool < Agents::Tool
  def self.name
    'search_knowledge_base'
  end

  description 'Busca en la base de conocimiento de Only Home (garantias, envios, ' \
              'cambios, politicas comerciales y casos de servicio resueltos) los ' \
              'fragmentos mas relevantes para responder una pregunta.'
  param :query, type: 'string', desc: 'Pregunta o frase a buscar en la base de conocimiento'

  MAX_RESULTS = 5

  def perform(tool_context, query:)
    account = resolve_account(tool_context)
    return 'No hay una cuenta configurada para la busqueda de conocimiento.' if account.blank?

    results = Knowledge::SearchService.new(account).search(query, limit: MAX_RESULTS)
    return 'No se encontro informacion relevante en la base de conocimiento.' if results.empty?

    format_results(results)
  rescue Knowledge::EmbeddingService::EmbeddingError, Knowledge::VectorStore::Error => e
    "La busqueda de conocimiento no esta disponible: #{e.message}"
  end

  private

  def resolve_account(tool_context)
    account_id = tool_context.context[:account_id]
    account_id.present? ? Account.find_by(id: account_id) : Account.first
  end

  def format_results(results)
    document_names = Knowledge::Document.where(id: results.pluck(:document_id).uniq)
                                        .pluck(:id, :name).to_h

    results.map.with_index(1) do |result, index|
      source = document_names[result[:document_id]] || 'desconocida'
      "[#{index}] Fuente: #{source} (relevancia #{result[:score]&.round(2)})\n#{result[:content]}"
    end.join("\n\n")
  end
end
