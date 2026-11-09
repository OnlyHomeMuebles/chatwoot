# frozen_string_literal: true

# ERP-15 (B3): al radicar con consultado_erp, escribe en la ficha la COMPRA (factura +
# productos) que el agente eligio en el selector, marcando la procedencia. CRUZA la factura
# y cada referencia contra el cache del ERP (helic3_erp_consultas): lo que existe en Siesa
# queda fuente erp; lo que se agrego a mano y no cruza, la fuente de quien lo escribio (humano
# desde el formulario, confirmado desde el agente de IA, ERP-16). No confia en que el
# frontend diga que algo vino de Siesa (mismo criterio que RegistrarClienteErp con el cliente).
#
# Los productos van a un jsonb (varios por factura); el primero tambien a los campos sueltos
# producto_nombre/referencia para lo que ya los lee. El ERP nunca bloquea: si la consulta
# falla, no cruza nada y todo queda con la fuente de quien lo escribio.
class Helic3::Casos::RegistrarCompraErp
  def initialize(ticket:, cedula:, datos:, fuente: :humano)
    @ticket = ticket
    @fuente = fuente.to_s
    @cedula = Helic3::Erp.normalizar_cedula(cedula)
    # { factura_numero:, factura_fecha:, productos: [{nombre:, referencia:}],
    #   producto_nombre:, producto_referencia: }  (los dos ultimos: lo que el agente
    #   escribio/edito a mano en "Compra", para el caso "no esta en la lista")
    @datos = datos.to_h.symbolize_keys
  end

  def call
    factura = factura_del_cache
    productos = ajustar_manual(cruzar_productos(factura))
    guardar(factura, productos)
  end

  private

  # La factura elegida, tal como la tiene el cache (lo que el wizard ya consulto; no re-llama
  # a Siesa dentro de la vigencia). nil si no hay cedula/factura, no cruza, o el ERP fallo.
  def factura_del_cache
    return nil if @cedula.blank? || @datos[:factura_numero].blank?

    compras = Helic3::Erp::Cache.consultar(account: @ticket.account, cedula: @cedula).compras
    buscar_factura(compras, @datos[:factura_numero].to_s)
  rescue StandardError => e
    Rails.logger.warn("[ERP-15] ERP no disponible al radicar compra ticket #{@ticket.id}: #{e.class.name}")
    nil
  end

  # ERP-16 (C4): primero el numero exacto; si no, el mismo numero en otro formato (p. ej. leido de
  # una foto). Solo cruza si es una sola factura: con dos candidatas (mismo numero, distinto
  # prefijo) no se adivina.
  def buscar_factura(compras, numero)
    exacta = compras.find { |f| f.numero.to_s == numero }
    return exacta if exacta

    candidatas = compras.select { |f| Helic3::Erp.misma_factura?(f.numero, numero) }
    candidatas.first if candidatas.one?
  end

  # Cada producto elegido, cruzado por referencia contra los items de la factura del cache:
  # si cruza, se toma el nombre+referencia del ERP (fuente erp); si no, lo que mando el agente
  # (con @fuente). Descarta entradas vacias.
  def cruzar_productos(factura)
    Array(@datos[:productos]).filter_map do |crudo|
      elegido = crudo.to_h.symbolize_keys
      item = cruzar_item(factura, elegido[:referencia])
      if item
        { 'nombre' => item.descripcion, 'referencia' => item.referencia, 'fuente' => 'erp' }
      elsif elegido[:nombre].present? || elegido[:referencia].present?
        { 'nombre' => elegido[:nombre], 'referencia' => elegido[:referencia], 'fuente' => @fuente }
      end
    end
  end

  def cruzar_item(factura, referencia)
    return nil if factura.nil? || referencia.blank?

    factura.items.find { |item| item.referencia.to_s == referencia.to_s }
  end

  # El agente tambien puede escribir el producto en "Compra" (lista del selector vacia, cliente
  # sin esa factura, o "no esta en la lista") o editar el nombre del que eligio. Eso queda fuente
  # @fuente. Si lo escrito coincide con el primero del selector, no se toca (se queda erp).
  def ajustar_manual(productos)
    manual = { 'nombre' => @datos[:producto_nombre].to_s.strip,
               'referencia' => @datos[:producto_referencia].to_s.strip, 'fuente' => @fuente }
    return productos if manual['nombre'].blank? && manual['referencia'].blank?
    return [manual] if productos.empty?
    return productos if mismo?(productos.first, manual)

    [manual] + productos[1..]
  end

  def mismo?(uno, otro)
    normal(uno['nombre']) == normal(otro['nombre']) && normal(uno['referencia']) == normal(otro['referencia'])
  end

  def normal(valor)
    valor.to_s.strip.downcase.gsub(/\s+/, ' ')
  end

  def guardar(factura, productos)
    ficha = @ticket.datos || @ticket.build_datos(account: @ticket.account)

    if factura
      # Cruza contra el cache: es de Siesa -> erp. factura_numero se sella aqui aunque Radicar
      # lo haya puesto provisional (el cruce verifica el origen; no es una edicion humana).
      sellar(ficha, 'factura_numero', factura.numero, 'erp')
      sellar(ficha, 'factura_fecha', factura.fecha, 'erp')
    else
      # No cruza: lo escrito queda con @fuente. En el formulario el numero ya lo puso Radicar
      # (mismo valor y fuente); el agente lo guarda despues de radicar, asi que se sella aqui.
      sellar(ficha, 'factura_numero', @datos[:factura_numero], @fuente)
      sellar(ficha, 'factura_fecha', @datos[:factura_fecha], @fuente)
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
