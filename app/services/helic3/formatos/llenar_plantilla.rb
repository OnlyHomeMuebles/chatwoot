# frozen_string_literal: true

# FMT-02: llena los marcadores {{NOMBRE}} de un .fodt (OpenDocument plano) con Nokogiri.
# Word parte el texto en varios text:span, asi que un {{CLIENTE}} puede quedar repartido;
# por eso se reconstruye el texto del parrafo, se ubica el marcador por posicion, el valor
# va al primer fragmento y lo que sobra del marcador se borra de los siguientes. El valor
# entra como TEXTO del nodo: Nokogiri lo escapa (un <script> o & no rompen el XML).
class Helic3::Formatos::LlenarPlantilla
  PATRON = /\{\{\s*([A-Z_]+)\s*\}\}/
  NS_TEXT = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'

  def self.call(fodt_xml, valores)
    new(fodt_xml).llenar(valores)
  end

  def self.marcadores_de(fodt_xml)
    new(fodt_xml).marcadores
  end

  def initialize(fodt_xml)
    @doc = Nokogiri::XML(fodt_xml)
  end

  def marcadores
    parrafos.flat_map { |parrafo| texto_de(parrafo).scan(PATRON).flatten }.uniq
  end

  def llenar(valores)
    parrafos.each { |parrafo| reemplazar_en(parrafo, valores) }
    # AS_XML sin FORMAT: no reindenta. Reformatear metería espacios entre los
    # text:span que LibreOffice podría pintar como espacios de más.
    @doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
  end

  private

  # parrafos y encabezados (incluye los de tablas, pies y cabeceras: todo en el mismo .fodt).
  def parrafos
    @doc.xpath('//text:p | //text:h', 'text' => NS_TEXT)
  end

  def nodos(parrafo)
    parrafo.xpath('.//text()')
  end

  def texto_de(parrafo)
    nodos(parrafo).map(&:content).join
  end

  # escanea el texto original UNA sola vez y reemplaza de DERECHA A IZQUIERDA. Asi los
  # indices de los marcadores a la izquierda no se corren por los reemplazos de la
  # derecha, y NUNCA se re-interpreta lo insertado: un valor que contenga {{X}} (dato del
  # cliente) queda literal y no cuelga el proceso.
  def reemplazar_en(parrafo, valores)
    lista = nodos(parrafo)
    completo = lista.map(&:content).join
    coincidencias = completo.to_enum(:scan, PATRON).map { Regexp.last_match }
    coincidencias.reverse_each do |coincidencia|
      valor = (valores[coincidencia[1]] || '').to_s.gsub(/\s*\n\s*/, ' ')
      aplicar(lista, coincidencia.begin(0), coincidencia.end(0), valor)
    end
  end

  # pone `valor` en el rango [desde, hasta): todo el valor va al primer nodo tocado;
  # en los siguientes se borra solo la parte del marcador que les corresponde.
  def aplicar(lista, desde, hasta, valor)
    pos = 0
    primero = true
    lista.each do |nodo|
      ini = pos
      fin = pos + nodo.content.length
      pos = fin
      next if fin <= desde || ini >= hasta

      nodo.content = recortar(nodo.content, [desde, ini].max - ini, [hasta, fin].min - ini, primero ? valor : '')
      primero = false
    end
  end

  # quita el tramo [ini, fin) del texto y mete `inserto` en su lugar.
  def recortar(texto, ini, fin, inserto)
    "#{texto[0...ini]}#{inserto}#{texto[fin..]}"
  end
end
