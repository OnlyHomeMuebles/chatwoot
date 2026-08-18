# frozen_string_literal: true

# Indexa la base de conocimiento de Only Home para el RAG: trocea cada sección en fragmentos
# semánticos (una tienda, un producto, un combo, una política, una FAQ), los embebe con el modelo
# local y los guarda en only_home_knowledge_chunks. Espejo OSS del pipeline de ingesta de Captain.
#
# Reindexar:  bundle exec rails runner "OnlyHome::KnowledgeIndexer.reindex!"
module OnlyHome::KnowledgeIndexer
  module_function

  def sections
    kb = OnlyHome::KnowledgeBase
    {
      'empresa' => kb::EMPRESA, 'catalogo' => kb::CATALOGO, 'combos' => kb::COMBOS,
      'tiendas' => kb::TIENDAS, 'politicas' => kb::POLITICAS, 'faq' => kb::FAQ,
      'quejas' => kb::QUEJAS_FRECUENTES
    }
  end

  # Reconstruye todo el índice desde cero. Devuelve la cantidad de chunks indexados.
  def reindex!
    chunks = build_chunks
    OnlyHome::KnowledgeChunk.transaction do
      OnlyHome::KnowledgeChunk.delete_all
      chunks.each do |c|
        OnlyHome::KnowledgeChunk.create!(**c, embedding: OnlyHome::Embeddings.embed(c[:content]))
      end
    end
    chunks.size
  end

  def build_chunks
    sections.flat_map { |category, text| chunk_section(category, text) }
  end

  # Divide una sección en chunks: bloques separados por línea en blanco; dentro de cada bloque con
  # viñetas ("- "), cada viñeta (con sus líneas de continuación) es un chunk, prefijado con el
  # encabezado del bloque para conservar el contexto (p. ej. la ciudad de una tienda).
  def chunk_section(category, text)
    text.split(/\n[ \t]*\n/).flat_map { |block| chunks_from_block(category, block.strip) }
  end

  def chunks_from_block(category, block)
    return [] if block.empty?

    lines = block.split("\n").map(&:rstrip)
    header = lines.first.strip.start_with?('-') ? nil : lines.first.strip
    bullets = split_bullets(lines)
    return [chunk(category, header, "#{category.upcase}: #{block}")] if bullets.empty?

    prefix = header ? "#{header} " : ''
    bullets.map { |b| chunk(category, header, "#{category.upcase} · #{prefix}#{b}".strip) }
  end

  def chunk(category, source, content)
    { category: category, source: source, content: content }
  end

  # Agrupa las líneas en viñetas: una viñeta empieza en "- " y absorbe las líneas de continuación.
  def split_bullets(lines)
    bullets = []
    lines.each do |line|
      s = line.strip
      if s.start_with?('- ')
        bullets << s.sub(/^- /, '')
      elsif bullets.any? && continuation?(s)
        bullets[-1] = "#{bullets.last} #{s}"
      end
    end
    bullets
  end

  def continuation?(text)
    !text.empty? && !text.end_with?(':')
  end
end
