# frozen_string_literal: true

# ERP-05: parser de la respuesta de API_v2_Ventas_Facturas_DesdePedido (Siesa HUB). Puro:
# del JSON de Siesa arma las facturas del contrato, agrupando las lineas por documento
# (f350_rowid). No hace red; el adaptador real le pasa la respuesta ya traida.
module Helic3::Erp::SiesaFacturas
  module_function

  # @param respuesta [Hash] el JSON que devuelve Siesa HUB
  # @return [Array<Helic3::Erp::Invoice>]  (vacio si no hay compras)
  def parsear(respuesta)
    filas(respuesta).group_by { |fila| fila['f350_rowid'] }.values.map { |lineas| factura(lineas) }
  end

  # v1: el nombre del cliente sale de la MISMA respuesta de compras (f200_razon_social_fact =
  # a quien se facturo). El cliente completo (ciudad, contacto) llega con la consulta de
  # clientes en ERP-12. nil si no hay compras (no hay de donde sacar el nombre).
  def nombre_cliente(respuesta)
    filas(respuesta).first&.dig('f200_razon_social_fact')&.strip.presence
  end

  # Filas de detalle, o [] si no hay tabla. Sin compras (codigo 1) Siesa manda `detalle` como
  # texto, no como {Table:[...]}, y a veces codigo llega como string: por eso se mira la forma
  # (hay tabla?), no el codigo. Sin tabla -> [], resultado valido, no un crash.
  def filas(respuesta)
    detalle = respuesta['detalle']
    tabla = detalle.is_a?(Hash) ? detalle['Table'] : nil
    tabla.is_a?(Array) ? tabla : []
  end

  def factura(lineas)
    cab = lineas.first
    Helic3::Erp::Invoice.new(
      numero: numero(cab),
      fecha: cab['f350_fecha'].to_s[0, 10], # recorta la hora: '2023-04-03T00:00:00' -> '2023-04-03'
      total: cab['f461_vlr_neto'],
      saldo: cab['f461_vlr_cxc'],
      estado: nil, # DesdePedido no trae pagada/pendiente/vencida; el selector no lo usa
      centro_operacion: cab['f350_id_co'],
      items: lineas.map { |linea| item(linea) }
    )
  end

  # Llave de factura = prefijo + consecutivo (doc de Jhan, 27-oct). El prefijo suele venir
  # en blanco; el formato exacto del Dash CX lo confirma ERP-12 (CA3).
  def numero(cab)
    "#{cab['f350_prefijo'].to_s.strip}#{cab['f350_consec_docto']}"
  end

  def item(linea)
    Helic3::Erp::InvoiceItem.new(
      referencia: linea['f120_referencia'],
      descripcion: linea['f120_descripcion'],
      cantidad: linea['f470_cant_1'],
      valor: linea['f470_vlr_neto']
    )
  end
end
