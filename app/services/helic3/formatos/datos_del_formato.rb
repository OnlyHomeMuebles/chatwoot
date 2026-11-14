# frozen_string_literal: true

# FMT-02: resuelve cada marcador a su texto, navegando desde el item de garantia
# hasta su expediente (ticket -> conversacion/contacto y ticket -> ficha). Los valores
# SIEMPRE salen como texto ('' si falta), nunca nil. DATOS_DE_EJEMPLO sirve para la
# vista previa sin un caso real.
class Helic3::Formatos::DatosDelFormato
  ZONA = 'America/Bogota'

  DATOS_DE_EJEMPLO = Helic3::Formatos::Marcadores::DICCIONARIO
                     .transform_values { |meta| meta[:ejemplo].to_s }.freeze

  # valores_producto (FMT-07): lo que el operador escribio en el modal. Se mezcla
  # ENCIMA de lo resuelto, solo para este documento; nunca toca la base.
  def self.call(item:, user:, valores_producto: {})
    new(item, user, valores_producto).call
  end

  # marcadores de la plantilla cuyo valor resuelto quedo vacio (para avisar al generar).
  def self.faltantes(plantilla, item:, user:)
    datos = call(item: item, user: user)
    Array(plantilla.marcadores).select { |marcador| datos[marcador].to_s.strip.empty? }
  end

  def initialize(item, user, valores_producto = {})
    @item = item
    @user = user
    @valores_producto = valores_producto || {}
    @garantia = item.garantia
    @ticket = @garantia.ticket
    @ficha = @ticket.datos
    @contacto = @ticket.conversation&.contact
  end

  # se arma por grupos (expediente, contacto, ficha, item) para mantener cada metodo
  # simple; al final se mezclan los valores del modal ENCIMA (solo para el documento).
  def call
    datos_generales.merge(datos_contacto, datos_ficha, datos_item, valores_producto_validos)
  end

  private

  def datos_generales
    {
      'FECHA' => Time.current.in_time_zone(ZONA).strftime('%d/%m/%Y'),
      'RADICADO' => @garantia.numero_radicado.to_s,
      'RADICADO_PQR' => @ticket.display_id.to_s,
      'FECHA_COMPRA' => fecha_compra,
      'ELABORADO_POR' => @user&.name.to_s
    }
  end

  # MAN-01: el cliente sale de la ficha si esta (PQR manual sin conversacion); si
  # no, del contacto de la conversacion, como venia funcionando para las del chat.
  def datos_contacto
    {
      'CLIENTE' => (@ficha&.cliente_nombre.presence || @contacto&.name).to_s,
      'TELEFONO' => (@ficha&.cliente_telefono.presence || @contacto&.phone_number).to_s
    }
  end

  def datos_ficha
    {
      'CEDULA' => @ficha&.cedula.to_s,
      'DIRECCION' => @ficha&.direccion.to_s,
      'CIUDAD' => @ficha&.ciudad.to_s,
      'FACTURA_NUMERO' => @ficha&.factura_numero.to_s
    }
  end

  def datos_item
    {
      'PRODUCTO' => @item.producto_nombre.to_s,
      'PRODUCTO_REFERENCIA' => @item.producto_referencia.to_s,
      # PRODUCTO_DESCRIPCION y PRODUCTO_NUEVO no tienen fuente en la base: nacen
      # vacios y solo los llena el operador en el modal (valores_producto).
      'PRODUCTO_DESCRIPCION' => '',
      'PRODUCTO_NUEVO' => '',
      'MOTIVO_GARANTIA' => @item.motivo_garantia&.nombre.to_s,
      'DETALLE' => @item.detalle_tipificado&.nombre.to_s,
      'DECISION' => @item.decision.to_s
    }
  end

  # solo las claves que son marcadores editables; cualquier otra se descarta (para
  # que un valor colado no pise un dato del expediente). Todo sale como texto.
  def valores_producto_validos
    @valores_producto.to_h.transform_keys(&:to_s)
                     .select { |clave, _valor| Helic3::Formatos::Marcadores.editable?(clave) }
                     .transform_values(&:to_s)
  end

  # MAN-01: la fecha de compra sale de la ficha (factura_fecha), en dd/mm/aaaa.
  # Vacio si no se registro. Antes dependia de "AGT-11", que nunca entro.
  def fecha_compra
    @ficha&.factura_fecha&.strftime('%d/%m/%Y').to_s
  end
end
