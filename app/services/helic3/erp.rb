# frozen_string_literal: true

# Fachada del modulo ERP: utilidades transversales a las consultas. ERP-10 arranca
# con la normalizacion de cedula; ERP-04 le sumara .adapter y .habilitado?.
module Helic3::Erp
  module_function

  # Deja la cedula lista para consultar y para usar como clave de cache: solo digitos,
  # sin el digito de verificacion (que en Colombia va despues de un guion). Ejemplos:
  #   '1.032.456.789' -> '1032456789'
  #   '900.123.456-7' -> '900123456'  (se descarta el DV '7')
  # Devuelve nil si quedan menos de 5 o mas de 15 digitos: no es una cedula/NIT valido
  # y no vale la pena gastar una consulta al ERP con eso.
  def normalizar_cedula(valor)
    # El DV es UN digito despues de un guion al final (900.123.456-7): se descarta solo
    # ese. Un guion en otra posicion (p. ej. usado como separador) NO corta la cedula.
    sin_dv = valor.to_s.strip.sub(/-\d\z/, '')
    digitos = sin_dv.gsub(/\D/, '')
    return nil if digitos.length < 5 || digitos.length > 15

    digitos
  end
end
