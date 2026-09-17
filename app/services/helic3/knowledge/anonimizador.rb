# frozen_string_literal: true

# AGT-05: enmascara los datos que identifican al titular ANTES de persistir una
# conversacion como material de voz. El corpus aprende la FORMA de atender (tono,
# lenguaje), nunca a quien se atendio. Guardarril del criterio: ningun chunk
# almacenado puede contener datos que identifiquen al titular — nombre, cedula,
# telefono, correo, direccion ni factura.
#
# Los nombres NO se adivinan: llegan exactos desde la conversacion (contacto y
# asesor asignado) y se enmascaran como literales antes de las regex. Eso resuelve
# el grueso del riesgo sin heuristica. Lo demas cae por patron. El orden importa:
# nombres -> correo -> direccion -> unidad -> factura -> barrido de numeros.
#
# Se enmascara de mas ante la duda con datos personales, pero se preserva a
# proposito lo que es VOZ y no identifica: precios (con $ o "pesos") y radicados
# (PQR-2026-00123), que son justo lo que el agente debe aprender a mencionar.
module Helic3::Knowledge::Anonimizador
  VIAS = 'calle|cll|carrera|cra|kra|kr|avenida|av|diagonal|diag|transversal|autopista|manzana|mz'
  # token de nomenclatura: numeral, "No"/"N°", cardinales/bis, numero con letra
  # (43A), o una letra suelta de nomenclatura (A, B) seguida de limite
  TOKEN_DIR = '\#|n[o°º]\.?|bis|sur|norte|este|oeste|\d+[a-z]?|[a-z](?=[\s\-#.,]|$)'
  UNIDADES = 'apto|apartamento|apart|casa|torre|bloque|interior|int|etapa|piso|local|oficina|of|conjunto|urbanizacion|urb'

  REGLAS = [
    # correo electronico
    [/[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}/i, '[correo]'],
    # direccion con via: consume la nomenclatura completa (incluye sufijos A/Sur/Bis/No)
    [/\b(?:#{VIAS})\b\.?(?:[\s\-.,]*(?:#{TOKEN_DIR}))+/i, '[direccion]'],
    # unidad de vivienda con numero (apto 502, torre 3, casa 12B)
    [/\b(?:#{UNIDADES})\.?\s*#?\s*\d+[a-z]?/i, '[direccion]'],
    # numero de factura junto a su palabra clave
    [/\b(?:factura|fact\.?|fac\.?)\s*(?:n[o°º]\.?\s*)?[:#]?\s*[a-z]{0,4}[\-\s]?\d{3,}/i, '[factura]'],
    # barrido de numeros largos (cedula, telefono): preserva radicados (letra-guion delante)
    # y precios (con $ delante o "pesos"/"COP"/"mil" detras)
    [/(?<![\w$.,-])\d[\d.\s-]{5,}\d(?![\w-])(?!\s*(?:pesos?|cop|mil|k\b))/i, '[numero]']
  ].freeze

  module_function

  # @param texto [String, nil]
  # @param nombres [Array<String>] nombres exactos a enmascarar (contacto, asesor)
  # @return [String] el texto con los datos del titular enmascarados
  def call(texto, nombres: [])
    return texto.to_s if texto.blank?

    resultado = enmascarar_nombres(texto.to_s, nombres)
    REGLAS.reduce(resultado) { |acc, (patron, reemplazo)| acc.gsub(patron, reemplazo) }
  end

  # Enmascara el nombre completo y cada palabra significativa (>= 4 letras) del
  # nombre, para atrapar tanto "soy Maria Fernanda Gomez" como un "gracias Fernanda"
  # mas adelante. Los mas largos primero para no partir un nombre completo.
  def enmascarar_nombres(texto, nombres)
    completos = Array(nombres).map { |n| n.to_s.strip }.reject { |n| n.length < 3 }
    tokens = completos.flat_map(&:split).reject { |t| t.length < 4 }
    literales = (completos + tokens).uniq.sort_by { |t| -t.length }

    literales.reduce(texto) do |acc, literal|
      acc.gsub(/\b#{Regexp.escape(literal)}\b/i, '[nombre]')
    end
  end
  private_class_method :enmascarar_nombres
end
