def knowledge_csv_to_text(path)
  rows = CSV.read(path, headers: true)
  rows.map do |row|
    row.to_h.filter_map { |key, value| "#{key}: #{value}" if value.present? }.join("\n")
  end.join("\n\n---\n\n")
end

namespace :knowledge do
  desc 'Ingest a URL into the knowledge base: rake "knowledge:ingest_url[https://example.com,Nombre]"'
  task :ingest_url, [:url, :name] => :environment do |_t, args|
    abort 'Usage: rake "knowledge:ingest_url[url,name]"' if args[:url].blank?

    account = Account.first
    content = Helic3::Knowledge::UrlFetcher.new(args[:url]).fetch

    document = Helic3::Knowledge::Document.find_or_initialize_by(account: account, external_link: args[:url])
    document.assign_attributes(name: args[:name].presence || args[:url], source_type: :url, content: content)
    document.save!

    result = Helic3::Knowledge::IngestionService.new(document).perform
    puts "#{document.name}: #{result} (#{document.chunks.count} fragmentos)"
  end

  desc 'Ingest every CSV dataset found in db/knowledge_seeds'
  task ingest_datasets: :environment do
    require 'csv'

    account = Account.first
    Dir[Rails.root.join('db/knowledge_seeds/*.csv')].each do |path|
      name = File.basename(path, '.csv')
      document = Helic3::Knowledge::Document.find_or_initialize_by(account: account, name: name, source_type: :dataset)
      document.assign_attributes(content: knowledge_csv_to_text(path))
      document.save!

      result = Helic3::Knowledge::IngestionService.new(document).perform
      puts "#{name}: #{result} (#{document.chunks.count} fragmentos)"
    end
  end
end

namespace :knowledge do
  desc 'Ingest (or refresh) the Only Home knowledge base into the RAG'
  task ingest_catalog: :environment do
    account = Account.first
    document = Helic3::Knowledge::Document.find_or_initialize_by(account: account, name: 'catalogo_helic3', source_type: :dataset)
    document.assign_attributes(content: Helic3::Agents::PoliticasEstaticas.full_text)
    document.save!

    result = Helic3::Knowledge::IngestionService.new(document).perform
    puts "catalogo_helic3: #{result} (#{document.chunks.count} fragmentos)"
  end
end

namespace :knowledge do
  desc 'Demo end-to-end: agente LLM + tool RAG. rake "knowledge:agent_demo[tiene garantia mi sofa]"'
  task :agent_demo, [:question] => :environment do |_t, args|
    question = args[:question].presence || 'Compre una cama de madera hace 8 meses y el enchapado se levanto. Tiene garantia?'

    Agents.configure { |config| config.openai_api_key = ENV.fetch('OPENAI_API_KEY') }

    agent = Agents::Agent.new(
      name: 'Asistente Only Home (demo)',
      instructions: 'Eres un asistente de soporte de Only Home, tienda de muebles en Colombia. ' \
                    'Antes de responder usa SIEMPRE la herramienta search_knowledge_base y basa tu ' \
                    'respuesta unicamente en lo que devuelva, mencionando la fuente. Si la base de ' \
                    'conocimiento no tiene la respuesta, dilo honestamente. Responde en espanol, breve.',
      model: 'gpt-4.1-mini',
      tools: [Helic3::KnowledgeBaseSearchTool.new]
    )

    result = Agents::Runner.with_agents(agent).run(question, context: { account_id: Account.first.id })
    puts "PREGUNTA: #{question}"
    puts "RESPUESTA: #{result.output}"
  end
end

namespace :knowledge do
  desc 'Search the knowledge base: rake "knowledge:search[como funciona la garantia]"'
  task :search, [:query] => :environment do |_t, args|
    abort 'Usage: rake "knowledge:search[query]"' if args[:query].blank?

    results = Helic3::Knowledge::SearchService.new(Account.first).search(args[:query])
    puts 'Sin resultados' if results.empty?
    results.each do |result|
      puts "score=#{result[:score]&.round(3)} doc=#{result[:document_id]} chunk=#{result[:chunk_id]}"
      puts result[:content].to_s[0, 300]
      puts '---'
    end
  end
end
