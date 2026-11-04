# frozen_string_literal: true

# COR-02: convierte una plantilla de correo (texto plano, {{MARCADOR}},
# **negrita**, parrafos separados por una linea en blanco) en el texto final
# que recibe el cliente. El orden importa: primero se sustituyen los
# marcadores con los datos reales (sin escapar), despues se escapa TODO el
# resultado, y solo entonces se aplican negrita/parrafos -- asi un {{CLIENTE}}
# que traiga un <script> (nombre mal digitado, dato de afuera) sale literal en
# el correo, nunca ejecutable.
module Helic3::Correos::Renderizar
  MARCADOR = /\{\{(\w+)\}\}/

  module_function

  # El asunto no lleva HTML; ademas se le quitan saltos de linea (defensa
  # basica contra inyeccion de cabeceras si un dato sustituido trajera uno).
  def asunto(texto, datos)
    sustituir(texto, datos).gsub(/[\r\n]+/, ' ').strip
  end

  def cuerpo_html(texto, datos)
    escapado = ERB::Util.html_escape(sustituir(texto, datos))
    escapado.split(/\n{2,}/).map { |parrafo| "<p>#{negrita(parrafo)}</p>" }.join
  end

  def sustituir(texto, datos)
    texto.to_s.gsub(MARCADOR) { datos[Regexp.last_match(1)].to_s }
  end

  def negrita(texto)
    texto.gsub(/\*\*(.+?)\*\*/m) { "<strong>#{Regexp.last_match(1)}</strong>" }
  end
end
