# Splits long text into overlapping chunks sized for embedding models.
# Cuts preferably at paragraph or sentence boundaries so fragments stay
# semantically coherent (mirrors the spirit of Captain's Q&A chunking
# while staying source-agnostic).
class Knowledge::ChunkingService
  MAX_CHUNK_SIZE = 1200
  OVERLAP = 150

  def initialize(text)
    @text = text.to_s.gsub(/\r\n?/, "\n").strip
  end

  def chunks
    return [] if @text.blank?
    return [@text] if @text.length <= MAX_CHUNK_SIZE

    build_chunks
  end

  private

  def build_chunks
    result = []
    start = 0
    while start < @text.length
      slice = cut_at_boundary(@text[start, MAX_CHUNK_SIZE], start)
      result << slice.strip
      start += [slice.length - OVERLAP, MAX_CHUNK_SIZE / 2].max
    end
    result.reject(&:blank?)
  end

  def cut_at_boundary(slice, start)
    return slice if start + MAX_CHUNK_SIZE >= @text.length

    boundary = slice.rindex("\n\n") || slice.rindex('. ') || slice.length
    boundary = slice.length if boundary < MAX_CHUNK_SIZE / 2
    slice[0, boundary + 1]
  end
end
