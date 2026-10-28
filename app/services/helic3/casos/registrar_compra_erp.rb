# frozen_string_literal: true

# ERP-15 (B3): al radicar con consultado_erp, escribe en la ficha la COMPRA (factura +
# productos) que el agente eligio en el selector, marcando la procedencia. CRUZA la factura
# y cada referencia contra el cache del ERP (helic3_erp_consultas): lo que existe en Siesa
# queda fuente erp; lo que el agente agrego a mano y no cruza, humano. No confia en que el
# frontend diga que algo vino de Siesa (mismo criterio que RegistrarClienteErp con el cliente).
#
# Los productos van a un jsonb (varios por factura); el primero tambien a los campos sueltos
# producto_nombre/referencia para lo que ya los lee. El ERP nunca bloquea: si la consulta
# falla, no cruza nada y todo queda humano.
class Helic3::Casos::RegistrarCompraErp
  def initialize(ticket:, cedula:, datos:)
    @ticket = ticket
    @cedula = Helic3::Erp.normalizar_cedula(cedula)
    @datos = datos.to_h.symbolize_keys # { factura_numero:, factura_fecha:, productos: [{nombre:, referencia:}] }
  end

  def call
    factura = factura_del_cache
    productos = cruzar_productos(factura)
    guardar(factura, productos)
  end

  private

  # La factura elegida, tal como la tiene el cache (lo que el wizard ya consulto; no re-llama
  # a Siesa dentro de la vigencia). nil si no hay cedula/factura, no cruza, o el ERP fallo.
  def factura_del_cache
    return nil if @cedula.blank? || @datos[:factura_numero].blank?

    compras = Helic3::Erp::Cache.consultar(account: @ticket.account, cedula: @cedula).compras
    compras.find { |f| f.numero.to_s == @datos[:factura_numero].to_s }
  rescue StandardError => e
    Rails.logger.warn("[ERP-15] ERP no disponible al radicar compra ticket #{@ticket.id}: #{e.class.name}")
    nil
  end

  # Cada producto elegido, cruzado por referencia contra los items de la factura del cache:
  # si cruza, se toma el nombre+referencia del ERP (fuente erp); si no, lo que mando el agente
  # (fuente humano). Descarta entradas vacias.
  def cruzar_productos(factura)
    Array(@datos[:productos]).filter_map do |crudo|
      elegido = crudo.to_h.symbolize_keys
      item = cruzar_item(factura, elegido[:referencia])
      if item
        { 'nombre' => item.descripcion, 'referencia' => item.referencia, 'fuente' => 'erp' }
      elsif elegido[:nombre].present? || elegido[:referencia].present?
        { 'nombre' => elegido[:nombre], 'referencia' => elegido[:referencia], 'fuente' => 'humano' }
      end
    end
  end

  def cruzar_item(factura, referencia)
    return nil if factura.nil? || referencia.blank?

    factura.items.find { |item| item.referencia.to_s == referencia.to_s }
  end

  def guardar(factura, productos)
    ficha = @ticket.datos || @ticket.build_datos(account: @ticket.account)

    if factura
      # Cruza contra el cache: es de Siesa -> erp. factura_numero se sella aqui aunque Radicar
      # lo haya puesto provisional (el cruce verifica el origen; no es una edicion humana).
      sellar(ficha, 'factura_numero', factura.numero, 'erp')
      sellar(ficha, 'factura_fecha', factura.fecha, 'erp')
    elsif @datos[:factura_fecha].present?
      # No cruza: la fecha que tecleo el agente queda humano (factura_numero ya lo puso Radicar).
      sellar(ficha, 'factura_fecha', @datos[:factura_fecha], 'humano')
    end

    ficha.productos = productos
    if (primero = productos.first)
      sellar(ficha, 'producto_nombre', primero['nombre'], primero['fuente'])
      sellar(ficha, 'producto_referencia', primero['referencia'], primero['fuente'])
    end

    ficha.save!
  end

  # Escritura directa de la compra (no pasa por RegistrarDatos): este servicio es la autoridad
  # de la compra en el flujo ERP y ademas guarda la lista de productos, que no es un campo suelto.
  def sellar(ficha, campo, valor, fuente)
    return if valor.blank?

    ficha[campo] = valor
    ficha.fuentes = ficha.fuentes.merge(campo => fuente)
  end
end
