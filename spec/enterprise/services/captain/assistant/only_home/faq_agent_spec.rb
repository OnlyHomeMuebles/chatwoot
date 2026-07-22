# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Assistant::OnlyHome::FaqAgent do
  subject(:agent) { described_class.build(model: 'gpt-4.1-mini') }

  it 'se construye como el especialista de conocimiento' do
    expect(agent.name).to eq('agente_faq')
    expect(agent.model).to eq('gpt-4.1-mini')
  end

  it 'tiene la tool de busqueda en la base de conocimiento (RAG)' do
    expect(agent.tools.map(&:class)).to include(KnowledgeBaseSearchTool)
  end

  it 'instruye usar la base de conocimiento y citar la fuente' do
    expect(described_class::INSTRUCTIONS).to include('search_knowledge_base')
    expect(described_class::INSTRUCTIONS).to match(/mencionando la fuente/i)
  end

  describe 'instrucciones' do
    it 'delimitan su responsabilidad al conocimiento de producto y políticas' do
      expect(described_class::INSTRUCTIONS).to match(/Conocimiento \(FAQ\)/)
      expect(described_class::INSTRUCTIONS).to match(/materiales/i)
    end

    it 'declaran las fronteras con los otros dominios (no PQRS, logística ni cotizaciones)' do
      expect(described_class::INSTRUCTIONS).to match(/No gestionas quejas/i)
      expect(described_class::INSTRUCTIONS).to match(/No consultas el estado/i)
      expect(described_class::INSTRUCTIONS).to match(/No generas precios/i)
    end

    it 'devuelven el control al triage cuando la solicitud no es de su dominio' do
      expect(described_class::INSTRUCTIONS).to include('agente_triage')
    end
  end
end
