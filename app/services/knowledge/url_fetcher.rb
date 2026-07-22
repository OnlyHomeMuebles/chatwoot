# Fetches a web page and extracts its readable text (scripts, styles and
# non-content tags stripped) for ingestion.
class Knowledge::UrlFetcher
  class FetchError < StandardError; end

  def initialize(url)
    @url = url
  end

  def fetch
    response = HTTParty.get(@url, headers: { 'User-Agent' => 'OnlyHome-KnowledgeBot/1.0' }, timeout: 30)
    raise FetchError, "Failed to fetch #{@url}: HTTP #{response.code}" unless response.success?

    extract_text(response.body)
  rescue SocketError, Timeout::Error, HTTParty::Error => e
    raise FetchError, "Failed to fetch #{@url}: #{e.message}"
  end

  private

  def extract_text(html)
    doc = Nokogiri::HTML(html)
    doc.css('script, style, noscript, iframe, svg').remove

    text = doc.css('body').text
    text.gsub(/[ \t]+/, ' ').gsub(/\n{3,}/, "\n\n").strip
  end
end
