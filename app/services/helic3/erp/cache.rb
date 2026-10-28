# frozen_string_literal: true

# ERP-14: cache por cuenta+cedula del resultado del ERP. El wizard, la radicacion y el
# agente leen lo MISMO sin volver a llamar a Siesa dentro de la vigencia (erp_cache_horas,
# 24 por defecto); "Volver a consultar" lo fuerza con refrescar:. Guarda solo los objetos
# de valor del contrato (serializados a jsonb), nunca el payload crudo de Siesa.
#
# La cedula debe venir ya normalizada (la clave del cache); los consumidores la normalizan
# con Helic3::Erp.normalizar_cedula antes de llamar aqui.
module Helic3::Erp::Cache
  HORAS_DEFECTO = 24
  Resultado = Data.define(:cliente, :compras) # cliente: Customer|nil, compras: [Invoice]

  module_function

  def consultar(account:, cedula:, refrescar: false)
    fila = Helic3::ErpConsulta.find_by(account_id: account.id, cedula: cedula)
    return hidratar(fila) if fila && !refrescar && vigente?(fila, account)

    desde_adaptador(account, cedula)
  end

  # Llama al ERP y guarda el resultado. Si el adaptador falla, propaga (no cachea un
  # error): el consumidor es quien decide seguir a mano (el ERP nunca bloquea).
  def desde_adaptador(account, cedula)
    cliente = Helic3::Erp.adapter.find_customer(cedula: cedula)
    compras = Helic3::Erp.adapter.invoices(cedula: cedula)
    guardar(account, cedula, cliente, compras)
    Resultado.new(cliente: cliente, compras: compras)
  end

  def guardar(account, cedula, cliente, compras)
    fila = Helic3::ErpConsulta.find_or_initialize_by(account_id: account.id, cedula: cedula)
    fila.update!(
      cliente: cliente&.to_h,
      compras: compras.map { |factura| serializar_factura(factura) },
      estado: cliente ? 'encontrado' : 'sin_cliente',
      consultado_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    # Carrera: otra consulta en vuelo (wizard dispara cliente+facturas a la vez) ya creo
    # la fila. No es error: el resultado recien traido se devuelve igual.
    nil
  end

  def hidratar(fila)
    Resultado.new(
      cliente: fila.cliente && Helic3::Erp::Customer.new(**fila.cliente.symbolize_keys),
      compras: fila.compras.map { |hash| rehidratar_factura(hash) }
    )
  end

  def vigente?(fila, account)
    fila.consultado_at && fila.consultado_at > horas(account).hours.ago
  end

  def horas(account)
    Helic3::Catalogo::Parametro.find_by(account_id: account.id, clave: 'erp_cache_horas')&.valor_entero ||
      HORAS_DEFECTO
  end

  def serializar_factura(factura)
    factura.to_h.merge(items: factura.items.map(&:to_h))
  end

  def rehidratar_factura(hash)
    datos = hash.symbolize_keys
    items = Array(datos[:items]).map { |item| Helic3::Erp::InvoiceItem.new(**item.symbolize_keys) }
    Helic3::Erp::Invoice.new(**datos.merge(items: items))
  end
end
