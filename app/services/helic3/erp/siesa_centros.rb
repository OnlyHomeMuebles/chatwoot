# frozen_string_literal: true

# ERP-18: parser de API_v4_CentrosOperacion (Siesa HUB). Puro: no hace red; el
# cliente HTTP (SiesaHubCliente) le pasa la respuesta ya traida.
#
# Esa consulta usa FOR JSON en el SQL, asi que Siesa parte el resultado en VARIAS
# filas de detalle.Table, cada una con un trozo de string (nombre de columna
# generado por SQL Server). Hay que UNIR los trozos en orden y recien ahi parsear:
# una fila sola no es JSON valido. El mismo f285_id se repite entre las 12 companias
# con nombres distintos (001 = "OM CALI SUR" o "INDIGO MALL"), por eso se indexa por
# compania + id. Los inactivos (f285_ind_estado 0) NO se filtran: facturas viejas
# siguen apuntando a ellos y deben mostrar su nombre.
module Helic3::Erp::SiesaCentros
  module_function

  # @return [Array<Hash>] centros {compania:, id:, nombre:, regional:, activo:}; [] si no hay tabla.
  def parsear(respuesta)
    JSON.parse(union(respuesta)).map { |fila| centro(fila) }
  rescue JSON::ParserError
    []
  end

  # nombre por compania + id EXACTOS (la misma id cambia de nombre entre companias). nil si no esta.
  def nombre(centros, compania:, id:)
    centros.find { |c| c[:compania] == compania && c[:id] == id.to_s }&.fetch(:nombre)
  end

  def centro(fila)
    {
      compania: fila['f285_id_cia'],
      id: fila['f285_id'].to_s,
      nombre: fila['f285_descripcion'].to_s.strip,
      regional: fila['f285_id_regional'],
      activo: fila['f285_ind_estado'] == 1
    }
  end

  # une el unico valor de cada fila de detalle.Table (en orden). '[]' si no hay tabla
  # (p. ej. "sin registros", que llega con detalle como texto, no como {Table:[...]}).
  def union(respuesta)
    detalle = respuesta['detalle']
    filas = detalle.is_a?(Hash) ? detalle['Table'] : nil
    return '[]' unless filas.is_a?(Array) && filas.any?

    filas.map { |fila| fila.values.first.to_s }.join
  end
end
