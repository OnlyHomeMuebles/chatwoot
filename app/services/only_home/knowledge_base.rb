# frozen_string_literal: true

# Base de conocimiento (datos INVENTADOS de Only Home) para que los agentes respondan con hechos
# concretos y no de forma genérica. Se inyecta en las instrucciones de los agentes que la necesitan.
# NOTA: son datos de ejemplo/demo, no reales.
module OnlyHome::KnowledgeBase
  # Catálogo con precios (COP)
  CATALOGO = <<~TXT.strip
    Catálogo y precios de Only Home (en pesos colombianos, COP):
    - Puerta Milano (MDF enchapado): $900.000 c/u
    - Puerta Roble Clásica (madera maciza): $1.200.000 c/u
    - Cocina integral: desde $1.500.000 por metro lineal (según acabado)
    - Closet a medida: desde $800.000 por metro lineal
    - Mueble de baño Aqua: $650.000 c/u
    - Acabados disponibles: melamina y MDF enchapado.
    - Financiación: hasta 12 cuotas con tarjeta; 10% de descuento pagando de contado.
  TXT

  # Políticas, tiempos, cobertura y contacto
  POLITICAS = <<~TXT.strip
    Políticas y operación de Only Home:
    - Garantía: 1 año en todos los productos por defectos de fabricación.
    - Tiempo de producción: 15 días hábiles desde la confirmación del pedido.
    - Cobertura de entrega e instalación: Bogotá, Medellín y Cali.
    - Costo de envío: gratis en compras superiores a $2.000.000; si no, $80.000.
    - Instalación: incluida en cocinas y closets; opcional ($120.000) en puertas.
    - Horario de atención: lunes a sábado, 8:00 a. m. a 6:00 p. m.
    - Devoluciones: hasta 5 días hábiles tras la entrega, si el producto no ha sido instalado.
  TXT
end
