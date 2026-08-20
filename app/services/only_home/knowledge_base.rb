# frozen_string_literal: true

# Base de conocimiento REAL de Only Home (marca comercial de OnlyMuebles), mueblería colombiana.
# Los datos provienen de las conversaciones reales de atención (WhatsApp/Messenger) y del sitio
# onlymuebles.com. Se inyecta en las instrucciones de los agentes para que respondan con hechos
# concretos y no de forma genérica.
#
# NOTA sobre precios: son precios de REFERENCIA en pesos colombianos (COP). Varían por acabado,
# color, promociones y vigencia; el agente debe presentarlos como referencia y confirmar
# disponibilidad/vigencia antes de cerrar una venta.
module OnlyHome::KnowledgeBase # rubocop:disable Metrics/ModuleLength
  # Identidad, canales, horarios y contacto.
  EMPRESA = <<~TXT.strip
    Only Home (marca de OnlyMuebles) es una mueblería colombiana. Vende muebles para el hogar:
    salas y sofás modulares, sofacamas, comedores, camas y bases, mesas de centro y de noche,
    sillas, colchonetas, cunas y combos para el hogar. NO fabrica puertas, cocinas integrales
    ni closets a medida.

    - Sitio web y compra en línea: https://www.onlymuebles.com
    - Política de tratamiento de datos: https://www.onlymuebles.com/aviso-de-privacidad
    - Canales de atención: WhatsApp y Messenger.
    - Línea de contacto / experiencia al cliente: 313 708 0076 (opción 2).
    - Compra por dos vías: tienda física y página web. Para el estado de un pedido se distingue
      si la compra fue "en tienda" o "en línea".

    Horarios de atención:
    - Área de Ventas: lunes a viernes 8:00 a. m. a 5:00 p. m. Sábados, domingos y festivos sin atención.
    - Área de Experiencia al Cliente (garantías y PQRS): lunes a viernes 8:00 a. m. a 4:00 p. m.,
      sábados 7:00 a 11:00 a. m. Domingos y festivos sin atención.
  TXT

  # Catálogo con precios de referencia (COP). Muchos productos tienen descuento vigente por temporada.
  CATALOGO = <<~TXT.strip
    Catálogo de Only Home (precios de referencia en COP; confirmar color/acabado, disponibilidad y vigencia):

    Salas y sofás modulares:
    - Sala Modular Santorini: se vende por módulos (cada módulo 1 m x 1 m). Sala desde $3.990.000
      (combo Sala + Comedor $4.990.000). Hay dos versiones.
    - Sofá Modular Mini Santorini (Verdi Oatmeal): $2.990.000. Silla Auxiliar Mini Santorini $827.000 c/u.
      Puff Mini Santorini $627.000.
    - Silla Auxiliar Santorini: $1.149.000.
    - Sofá Modular Olive: $5.499.000. Sofá Olive 2 puestos: $3.199.000. Silla auxiliar Olive: $1.799.000.
    - Sofá Grecia 2 puestos: $3.079.000 (con descuento $2.463.200).
    - Sofacama Boston / Houston: $2.989.000 (con descuento $2.391.200).
    - Sofacama Merida (Arena Verdi Ivory): $1.269.000.

    Camas y bases:
    - Cama King Sion (Arena o Roble): $4.439.000 (con descuento entre $3.107.300 y $3.551.200).
    - Cama King Lenon Regia (Gris Hielo): $6.989.000 (con descuento $4.542.850).
    - Cama Sion Queen: $3.449.000 (con descuento $2.414.300).
    - Cama Bianco Semidoble (crema o beige): $2.699.000 (con descuento $1.889.300).
    - Cama Salvatore Semidoble (beige o plomo): $2.519.000 (con descuento $1.763.300).
    - Base Cama Doble (Arena/Madera): $1.199.000 (con descuento $839.300).
    - Base Cama Queen (Arena/Madera): $1.499.000 (con descuento $1.049.300).
    - Base Cama Queen Madera Roble: $2.199.000 (con descuento $1.759.200).
    - Base Cama Semidoble Arena: $999.000 (con descuento $699.300).
    - Set Dormitorio Mini Palermo Roble Santana + colchón: $2.399.000 (incluye obsequio protector de colchón).
    - Cuna Evolutiva Rory: $1.790.000. También hay Cama Cuna Elise.

    Comedores, mesas y sillas:
    - Mesa de Comedor 6 puestos Sion (Arena): $3.839.000 (con descuento $3.071.200).
      Solo la mesa Sion Avellana 6 puestos: $1.919.400 (la mesa, sin sillas).
    - Mesa de Comedor 4 puestos Ana: $549.000 (con descuento $329.400).
    - Mesa de Comedor Boston / Merida: $709.000 a $799.000.
    - Mesa de Centro Sion Circular (Arena/Avellana): $1.369.000 (con descuento $1.095.200).
    - Mesa de Centro Beta Grande Arena: $409.000 (con descuento $286.300).
    - Mesas de Noche: Merida $439.000; Ensueño $389.000; Malaga Roble $718.000; Armany Avellana $579.000.
    - Silla de Comedor Isola $739.000. Silla de Comedor Toronto $369.000.
    - Biffet/Bufet Sion Roble: $1.849.000 (con descuento $1.479.200).

    Colchonetas LYNO (para cunas y camas nicho):
    - Rory 0,72 x 0,62 m: $590.000 a $609.000. Rory 1,22 x 0,62 m: $690.000 a $819.000.
    - Noah 100 x 0,70 m: $709.000. Elise 100 x 190 m: $809.000.
  TXT

  # Combos para el hogar (los más promocionados). IMPORTANTE: los combos son FIJOS, NO modificables:
  # no se quitan ni se cambian elementos.
  COMBOS = <<~TXT.strip
    Combos para el hogar de Only Home (combos fijos, NO modificables — no se quitan ni cambian piezas):

    - Combo Hogar Merida — $4.990.000: sofácama, dos puff, mesa de centro, mesa de comedor con 3
      sillas y una banca, cama doble y mesa de noche. Tela Verdi Ivory y madera tono arena.
      Ideal para espacios pequeños.
    - Combo Hogar Beta — $3.990.000: sala con sofá modular Beta y mesa de centro Catalina; comedor
      de 4 puestos (mesa Calypso + 4 sillas Toronto); alcoba con cama doble Bareim (no incluye
      colchón) y mesa de noche Ensueño. Madera nuez, caoba o blanca; tapizado beige o gris.
      Envío y armado gratis en rutas seleccionadas.
    - Combo Boston — $5.990.000: sofácama multifuncional, mesa de centro, comedor de 4 puestos y
      dormitorio con cama doble y mesa de noche. Madera tono arena, tapizado beige.
    - Combo Dana — $4.610.000: sala con sofá Oslo 2 puestos, dos sillas auxiliares Samanta y juego
      de mesas Nano; comedor de 4 puestos (mesa Dana + sillas Nova). Madera nuez; tapizado beige o
      gris. Envío y armado gratis en rutas seleccionadas. Disponible para compra por página web.
  TXT

  # Tiendas físicas por ciudad (dirección, horario, teléfono y correo).
  TIENDAS = <<~TXT.strip
    Tiendas Only Home:

    Bogotá:
    - OH Bogotá Paseo: C.C. Paseo Villa del Río, Diagonal 57 C Sur No. 62-60, Segundo Nivel Local 252.
      Lunes a domingo 10:00 a. m.-8:00 p. m. Tel: 3125905161. bogotapaseo@onlyhome.co
    - OH Plaza de las Américas: Cra. 71d #6-94 Sur, Kennedy, Local 1640. Lunes a domingo
      10:00 a. m.-8:00 p. m. Tel: 3114717473. plazalasamericas@onlyhome.co
    - OH Diver Plaza: Local 130 D, primer nivel, Transversal 99 70a-89, Engativá. Lunes a domingo
      10:00 a. m.-7:00 p. m. Tel: 3108032131. diverplaza@onlyhome.co

    Cali:
    - OH Cali Sur: Cra 56 #13-55, Barrio 1 de Mayo. Lunes a sábado 9:00 a. m.-7:00 p. m. jornada
      continua; domingos y festivos 10:00 a. m.-4:00 p. m. Tel: 3137080069. onlysur@onlyhome.co
    - OH Cali Norte: Cra 1 #44-02. Lunes a sábado 9:00 a. m.-7:00 p. m. jornada continua; domingos y
      festivos 10:00 a. m.-4:00 p. m. Tel: 3137080071. norte@onlyhome.co
    - OH Outlet Juanchito: Km 4 vía Cali-Candelaria. Lunes a sábado 9:00 a. m.-6:00 p. m. jornada
      continua; domingos y festivos 10:00 a. m.-4:00 p. m. Tel: 3102121690. juanchitocali@onlyhome.co

    Eje Cafetero y Tolima:
    - OH Manizales Fundadores: C.C. Fundadores, nivel -1. Lunes a domingo 10:00 a. m.-8:00 p. m.
      Tel: 3123384252. fundadoresmanizales@onlyhome.co
    - OH El Cable (Manizales): Cra 23 #62-99, pisos 2 y 3, frente a Farmatodo, Av. Santander.
      Lunes a sábado 9:00 a. m.-7:00 p. m., domingo sin atención; festivos 10:00 a. m.-4:00 p. m.
      Tel: 3137080072. elcablemanizales@onlyhome.co
    - OH Pereira La Octava: Cra. 8 #22-36. Lunes a sábado 9:00 a. m.-7:00 p. m. jornada continua;
      domingos y festivos 10:00 a. m.-4:00 p. m. Tel: 3125183730. laoctava@onlyhome.co
    - OH Armenia La Tebaida: Km 6 vía La Tebaida. Lunes a sábado 9:00 a. m.-6:00 p. m.; domingos y
      festivos 10:00 a. m.-4:00 p. m. Tel: 3137080068. saladeexhibicion@onlyhome.co
    - OH Armenia Plaza Flora: Av. Centenario Cll 3, Lote Nápoles, frente al C.C. Plaza Flora.
      Lunes a sábado 9:00 a. m.-7:00 p. m.; domingos y festivos 10:00 a. m.-4:00 p. m.
      Tel: 3104019161. axm@onlyhome.co
    - OH Ibagué Guabinal: Urbanización Arkamónica Mz G, local 1, Ibagué, Tolima. Lunes a sábado
      9:00 a. m.-7:00 p. m., domingo sin atención. Tel: 3102566080. guabinal@onlyhome.co

    Sur-occidente:
    - OH Palmira Unicentro: C.C. Unicentro, Calle 42 #39-68, local 152. Lunes a domingo
      10:00 a. m.-8:00 p. m. Tel: 3134058724. unicentropalmira@onlyhome.co
    - OH Popayán Terraplaza: C.C. Terraplaza, local 122. Lunes a domingo 10:00 a. m.-8:00 p. m.
      Tel: 3108900563. terraplazapopayan@onlyhome.co
    - OH Neiva Santa Lucía: C.C. Santa Lucía Plaza, local N 2-25, Neiva, Huila. Lunes a domingo
      10:00 a. m.-8:00 p. m. Tel: 3134058714. santalucia@onlyhome.co
    - OH Buenaventura Centro: Calle 2da #3-54. Lunes a sábado 9:00 a. m.-6:00 p. m., domingo sin
      atención. Tel: 3137080074. buenaventuracentro@onlyhome.co
    - OH Buenaventura El Pailón: Cra. 66 #1-169. Lunes a sábado 9:00 a. m.-6:00 p. m., domingo sin
      atención. Tel: 3116391010. buenaventura@onlyhome.co
  TXT

  # Políticas y operación: formas de pago, envío/entrega, garantía y devoluciones.
  POLITICAS = <<~TXT.strip
    Políticas y operación de Only Home:

    Formas de pago:
    - Se acepta: efectivo, tarjeta de crédito/débito, Sistecrédito y Addi.
    - NO se maneja: crédito directo, crédito con Brilla, ni pago contra entrega.
    - Compras por página web: se paga con link de pago de Mercado Pago.
    - Sistecrédito se tramita únicamente en tienda física (se validan existencias).

    Envío y entrega:
    - Los envíos se realizan con RUTA PROPIA (transporte de la empresa), no con transportadoras externas.
    - Envío sin costo adicional en las ciudades y municipios que cubren las rutas establecidas.
    - Tiempo de entrega estimado: de 20 a 30 días hábiles según la ciudad (p. ej. Bogotá 20-25 días,
      Medellín 25-30 días hábiles). No hay envío express: las rutas tienen frecuencias fijas y a
      algunas zonas se llega aproximadamente una vez al mes.
    - No hay cobertura fuera de las rutas establecidas (por ejemplo, no se envía a Barranquilla).
    - En varios combos el envío y el armado son gratis en rutas seleccionadas.

    Garantía (área de Experiencia al Cliente):
    - Todos los muebles tienen garantía por defectos de fabricación.
    - Los muebles de madera tienen garantía de hasta 10 años por enfermedad de la madera.
    - Qué NO cubre la garantía: el desgaste normal por el uso; el mal uso, golpes o daños accidentales;
      manchas o daños por líquidos; la exposición extrema al sol o a la humedad; y las modificaciones
      o reparaciones hechas por el cliente o por terceros.
    - Para tramitar una garantía se requiere: factura de compra, fotos del producto donde se
      evidencien los inconvenientes, y los datos del cliente (nombre completo, número de cédula,
      dirección completa y ciudad).
    - Un técnico especializado visita en un plazo de 12 a 15 días hábiles y se contacta directamente
      con el cliente. Si se requiere verificación, se programa la recolección del producto dentro de
      los 15 días hábiles siguientes; se avisa un día antes de la visita.

    Devoluciones y retracto:
    - Aplica el derecho de retracto para cancelar una compra dentro del término legal.
    - Los reembolsos se gestionan por el medio de pago (por ejemplo, devolución a la cuenta de
      Mercado Pago en compras en línea).
  TXT

  # Preguntas frecuentes reales (las que más entran por WhatsApp/Messenger) con su respuesta.
  FAQ = <<~TXT.strip
    Preguntas frecuentes de clientes (con la respuesta correcta):

    - "¿Cuál es el precio del Sofá Modular Santorini?" → Es una sala modular que se vende por módulos
      (cada módulo 1 m x 1 m); la sala está desde $3.990.000 y el combo Sala + Comedor en $4.990.000.
      La versión Mini Santorini está desde $2.990.000.
    - "¿Se puede personalizar la configuración de los módulos / alguna pieza?" → Los COMBOS son fijos,
      no se modifican. Las salas modulares Santorini sí se arman por módulos: el cliente elige la
      cantidad de módulos y el color disponible.
    - "¿Ofrecen entrega a domicilio en Cali / en otras ciudades / en todo el país?" → Sí, con ruta
      propia, en las ciudades y municipios que cubren las rutas, con envío sin costo. Fuera de esas
      rutas no hay cobertura.
    - "¿Cuáles son los materiales de las cunas?" → Cuna evolutiva en madera; se complementan con
      colchonetas LYNO (Rory, Noah, Elise).
    - "¿Cuándo sale / dónde veo la nueva colección Olive?" → La colección Olive está disponible; se
      puede ver y comprar en https://www.onlymuebles.com
    - "¿Puedo encontrar estos precios en línea también?" → Sí, en https://www.onlymuebles.com
    - "¿Hasta cuándo dura la promoción? ¿Es válida en todas las tiendas? ¿Qué productos tienen
      descuento?" → Hay promociones con fecha de vigencia; conviene confirmar la vigencia y la tienda,
      ya que los descuentos pueden variar por punto de venta.
    - "¿Qué formas de pago / financiación manejan?" → Efectivo, tarjeta, Sistecrédito y Addi
      (no se maneja pago contra entrega).
    - "¿Qué garantía tienen y qué cubre?" → Todos los muebles tienen garantía por defectos de
      fabricación; la madera hasta 10 años por enfermedad de la madera. No cubre desgaste normal,
      mal uso, golpes/accidentes, daños por líquidos, sol/humedad extremos ni modificaciones del
      cliente. Para hacerla efectiva: factura + fotos del daño + datos; un técnico visita en 12 a
      15 días hábiles.
    - "¿Cómo cuido / limpio mis muebles?" → Madera: límpiala con un paño suave apenas húmedo y sécala;
      evita el sol directo prolongado, la humedad y los productos abrasivos. Tapizados/tela: aspira o
      pasa un paño con agua y jabón neutro, sin empapar. Evita apoyar objetos calientes o cortopunzantes.
    - "¿El armado o la instalación están incluidos?" → En productos sueltos, por lo general el armado
      corre por cuenta del cliente; en varios combos el envío y el armado son gratis en las rutas
      seleccionadas.
    - "¿Hacen muebles totalmente a la medida?" → No se fabrican muebles a la medida. Sí puedes armar
      las salas modulares (p. ej. Santorini) eligiendo la cantidad de módulos y el color disponible.
    - "¿Puedo comprar en línea? ¿Y recoger en tienda?" → Sí, puedes comprar en https://www.onlymuebles.com;
      la entrega se hace con ruta propia. Si prefieres recoger en una tienda, confírmalo directamente
      con la tienda de tu ciudad, porque depende de la disponibilidad del producto.
  TXT

  # Tipos de queja/reclamo que entran a menudo (para orientar al agente de PQRS). Ordenadas por
  # frecuencia observada en las conversaciones reales.
  QUEJAS_FRECUENTES = <<~TXT.strip
    Tipos de queja/reclamo más frecuentes (PQRS). Trátalas con empatía y recopila factura, fotos y
    datos del cliente cuando aplique:

    1. Demoras o incumplimiento en la entrega: entregas reprogramadas, "me habían programado la
       entrega y no ha llegado", rutas que no cumplen la fecha, largos tiempos de espera. Es la queja
       MÁS común. Explica los tiempos y frecuencias de ruta y ofrece hacer seguimiento.
    2. Producto defectuoso o con fallas de calidad: acabado no uniforme, textura tosca, puntos negros
       en la madera, piezas dañadas/rotas, asientos en mal estado. Encausa a garantía (factura + fotos).
    3. Solicitud de devolución de dinero / reembolso / derecho de retracto: compras que se quieren
       cancelar, dinero a favor pendiente de devolución.
    4. Garantía sin resolver a tiempo o inconformidad con el proceso: "hice una PQRS hace semanas y no
       me responden", garantías que el cliente siente que no se cumplen.
    5. Falta de respuesta o seguimiento: "nadie responde", "pésimo servicio", "mucha demora".
    6. Problemas en la entrega física: no fue posible ingresar el producto a la vivienda, novedades de
       dirección o fecha de entrega.
  TXT

  # Texto completo del conocimiento de Only Home, usado para ingerirlo al RAG (búsqueda semántica).
  def self.full_text
    [EMPRESA, CATALOGO, COMBOS, TIENDAS, POLITICAS, FAQ, QUEJAS_FRECUENTES].join("\n\n---\n\n")
  end
end
