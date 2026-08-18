require 'rails_helper'

RSpec.describe KnowledgeBaseSearchTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new }
  let(:tool_context) { instance_double(Agents::ToolContext, context: { account_id: account.id }) }

  describe '#perform' do
    context 'when the knowledge base has relevant content' do
      it 'returns formatted results with their source' do
        document = Knowledge::Document.create!(account: account, name: 'Manual de Garantia', source_type: :url,
                                               external_link: 'https://example.com', content: 'contenido')
        results = [{ chunk_id: 1, score: 0.87, content: 'Garantia de 1 año en madera', document_id: document.id }]

        search_service = instance_double(Knowledge::SearchService, search: results)
        allow(Knowledge::SearchService).to receive(:new).with(account).and_return(search_service)

        output = tool.perform(tool_context, query: 'garantia de muebles')

        expect(output).to include('Manual de Garantia')
        expect(output).to include('Garantia de 1 año en madera')
        expect(output).to include('0.87')
      end
    end

    context 'when nothing matches' do
      it 'returns an explicit empty message so the llm does not hallucinate' do
        search_service = instance_double(Knowledge::SearchService, search: [])
        allow(Knowledge::SearchService).to receive(:new).and_return(search_service)

        output = tool.perform(tool_context, query: 'algo inexistente')

        expect(output).to eq('No se encontro informacion relevante en la base de conocimiento.')
      end
    end

    context 'when the vector store is unavailable' do
      it 'returns an error message instead of raising' do
        allow(Knowledge::SearchService).to receive(:new)
          .and_raise(Knowledge::VectorStore::Error, 'vector store caido')

        output = tool.perform(tool_context, query: 'garantia')

        expect(output).to include('no esta disponible')
        expect(output).to include('vector store caido')
      end
    end
  end
end
