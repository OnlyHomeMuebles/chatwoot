# frozen_string_literal: true

# AGT-05: enmascara los datos personales del cliente ANTES de persistir una
# conversacion como material de voz. El corpus aprende la FORMA de atender (tono,
# lenguaje), nunca los datos del cliente. Es el guardarril del criterio: ningun
# chunk almacenado puede contener cedula, telefono, correo, direccion ni factura.
#
# El orden de las reglas importa: primero los patrones especificos (correo,
# direccion, factura con su palabra clave) y de ultimo un barrido de cualquier
# secuencia larga de digitos, que atrapa cedulas, telefonos y facturas sueltas
# que los patrones especificos no hayan cubierto. Ante la duda, enmascara de mas:
# preferimos perder un dato de dialogo antes que filtrar un dato del cliente.
module Helic3::Knowledge::Anonimizador
  REGLAS = [
    # correo electronico
    [/[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}/i, '[correo]'],
    # direccion (nomenclatura urbana colombiana): via + numeros
    [/\b(?:calle|cll|carrera|cra|kra|kr|avenida|av|diagonal|diag|transversal|trans|tv|manzana|mz|autopista)\b\.?\s*#?\s*\d+[\s#\-.\d]*\d/i,
     '[direccion]'],
    # numero de factura junto a su palabra clave (no marca cualquier numero como factura)
    [/\b(?:factura|fact\.?|fac\.?)\s*(?:n[o°º]\.?\s*)?[:#]?\s*[a-z]{0,4}[\-\s]?\d{3,}/i, '[factura]'],
    # barrido final: secuencia larga de digitos (cedula, telefono, factura suelta)
    [/\d[\d\s.\-]{5,}\d/, '[numero]']
  ].freeze

  module_function

  # @param texto [String, nil]
  # @return [String] el mismo texto con los datos personales enmascarados
  def call(texto)
    return texto.to_s if texto.blank?

    REGLAS.reduce(texto.to_s) { |acc, (patron, reemplazo)| acc.gsub(patron, reemplazo) }
  end
end
