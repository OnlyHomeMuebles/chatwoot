# frozen_string_literal: true

# ERP-05: parser de la consulta de clientes de Siesa HUB, filtrada por cedula. Trae de CUALQUIER
# cliente (tenga compras o no): identificacion, nombre y contacto (telefono, correo, direccion).
# La ciudad viene como codigo (idCiudad/idDepto DANE), no como nombre, asi que queda nil por ahora
# (traducir el codigo a nombre es un follow-up con su catalogo). La consulta devuelve una fila por
# empresa del grupo (idCia 1..n), todas iguales para el tercero: se toma la primera.
module Helic3::Erp::SiesaClientes
  module_function

  # @return [Helic3::Erp::Customer, nil] nil si la cedula no esta en el maestro.
  def parsear(respuesta, cedula:)
    fila = filas(respuesta).first
    return nil if fila.nil?

    nombre = nombre_de(fila)
    return nil if nombre.blank?

    Helic3::Erp::Customer.new(
      cedula: cedula, nombre: nombre,
      telefono: fila['telefono'].presence, email: fila['email'].presence,
      direccion: fila['direccion1'].presence, ciudad: nil
    )
  end

  # Para una persona arma "Nombres Apellido1 Apellido2" (orden natural); para una empresa,
  # que no tiene nombres, usa la razon social tal cual.
  def nombre_de(fila)
    nombres = fila['nombres'].to_s.strip
    if nombres.present?
      [nombres, fila['apellido1'], fila['apellido2']]
        .map { |parte| parte.to_s.strip }.reject(&:blank?).join(' ')
    else
      fila['razonSocial'].to_s.strip.gsub(/\s+/, ' ')
    end
  end

  # Filas de detalle, o [] si no hay tabla (sin registros / payload de error), robusto a que
  # `detalle` venga como texto en vez de {Table:[...]}.
  def filas(respuesta)
    detalle = respuesta['detalle']
    tabla = detalle.is_a?(Hash) ? detalle['Table'] : nil
    tabla.is_a?(Array) ? tabla : []
  end
end
