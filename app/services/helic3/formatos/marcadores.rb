# frozen_string_literal: true

# FMT-02: contrato de que datos expone el sistema a las plantillas. No son valores de
# negocio (esos salen del expediente): es la lista de marcadores validos y su ejemplo
# para la vista previa. Por eso vive en codigo. Sintaxis en la plantilla: {{NOMBRE}}.
module Helic3::Formatos::Marcadores
  DICCIONARIO = {
    'FECHA' => { descripcion: 'Fecha de generación (dd/mm/aaaa)', ejemplo: '05/10/2026' },
    'RADICADO' => { descripcion: 'Radicado de la garantía', ejemplo: 'GAR-0001' },
    'RADICADO_PQR' => { descripcion: 'Consecutivo del expediente', ejemplo: '1234' },
    'CLIENTE' => { descripcion: 'Nombre del cliente', ejemplo: 'Cliente de Ejemplo' },
    'TELEFONO' => { descripcion: 'Teléfono del cliente', ejemplo: '3001234567' },
    'CEDULA' => { descripcion: 'Cédula del cliente', ejemplo: '1.234.567' },
    'DIRECCION' => { descripcion: 'Dirección del cliente', ejemplo: 'Calle 1 # 2-3' },
    'CIUDAD' => { descripcion: 'Ciudad del cliente', ejemplo: 'Cali' },
    'FACTURA_NUMERO' => { descripcion: 'Número de factura', ejemplo: 'FAC-999' },
    'FECHA_COMPRA' => { descripcion: 'Fecha de compra (AGT-11, aún no disponible)', ejemplo: '' },
    'PRODUCTO' => { descripcion: 'Nombre del producto', ejemplo: 'Sofá Milano' },
    'PRODUCTO_REFERENCIA' => { descripcion: 'Referencia del producto', ejemplo: 'REF-123' },
    'MOTIVO_GARANTIA' => { descripcion: 'Motivo de garantía', ejemplo: 'Falla de fábrica' },
    'DETALLE' => { descripcion: 'Detalle tipificado', ejemplo: 'Chapilla levantada' },
    'DECISION' => { descripcion: 'Decisión del ítem', ejemplo: 'Cambio de producto' },
    'ELABORADO_POR' => { descripcion: 'Quien genera el formato', ejemplo: 'Asesora SAC' }
  }.freeze

  def self.conocido?(nombre)
    DICCIONARIO.key?(nombre)
  end

  def self.nombres
    DICCIONARIO.keys
  end
end
