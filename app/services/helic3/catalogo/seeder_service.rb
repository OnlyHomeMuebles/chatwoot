# Siembra los catalogos de clasificacion de CAT-01 con los valores del
# diseno validado con Only Home (asignacion del 21/08) y del correo del area
# del 04/08. Idempotente por diseno (criterio 5): la llave natural es el
# codigo por cuenta y el indice unico de cada tabla es la red de seguridad.
#
# Los nombres del correo se conservan LITERALES como los escribio el area
# (incluidas posibles erratas como "Chapilla leventada"): corregirlos sin
# confirmacion seria resolver por cuenta propia.
#
# Lo que el area aun no confirma NO se siembra (MotivoPqr y Resultado) o se
# siembra con el campo en null (plazos por tipo, origen de ruta). La lista
# completa esta en app/models/helic3/catalogo/PENDIENTES.md.
class Helic3::Catalogo::SeederService
  CATEGORIAS = %w[Garantía Servicio Comercial Logística Facturación Información].freeze

  # el plazo legal por tipo queda null hasta que el area lo confirme
  TIPOS = %w[Petición Queja Reclamo Sugerencia Felicitación].freeze

  # detiene_reloj queda false en todas hasta confirmar cuales pausan el plazo
  ETAPAS_PQR = ['Nueva', 'En análisis', 'Respondida', 'Cerrada'].freeze

  # correo del area (04/08) + regla del criterio 7 de CAT-01: reparacion
  # aplica hasta 30 dias inclusive desde la entrega; calidad desde el dia 31
  MOTIVOS_GARANTIA = [
    { nombre: 'Error de pedido - tienda', codigo: 'error_pedido_tienda' },
    { nombre: 'Error de pedido - Logistica', codigo: 'error_pedido_logistica' },
    { nombre: 'Calidad - producto comprado', codigo: 'calidad_producto_comprado',
      regla: 'dias_desde_entrega_minimo', parametro_dias: 31 },
    { nombre: 'Reparación - primera entrega', codigo: 'reparacion_primera_entrega',
      regla: 'dias_desde_entrega_maximo', parametro_dias: 30 },
    { nombre: 'Devoluciones primera entrega', codigo: 'devoluciones_primera_entrega' }
  ].freeze

  # 31 detalles literales del correo, mapeados PROVISIONALMENTE por afinidad
  # (el area no entrego el mapeo detalle->motivo; la asignacion es CAT-01
  # pendiente numero 4). El PDF de asignacion habla de 28 detalles "acordados
  # con produccion": la diferencia con estos 31 esta pendiente de conciliar.
  DETALLES_POR_MOTIVO = {
    'error_pedido_tienda' => [
      'Referencia diferente a la solicitada',
      'Referencia incorrecta',
      'Falta de asesoría en la venta'
    ],
    'error_pedido_logistica' => [
      'Producto roto en entrega',
      'Entrega parcial',
      'Falta de piezas o manuales',
      'Entrega fuera de plazo'
    ],
    'calidad_producto_comprado' => [
      'Producto inestable / cojo',
      'Producto desajustado',
      'Producto fracturado o roto',
      'Producto dilatado',
      'Herraje oxidado o defectuoso',
      'Producto mal pintado',
      'Chapilla leventada',
      'Baja densidad de espuma',
      'Tela destemplada',
      'Falla en acabados o alineación',
      'Producto rayado',
      'Producto sucio',
      'Variación en el tono',
      'Tonos diferentes entre productos',
      'Productos decolorado',
      'Tela motosa',
      'Tela o madera diferente',
      'Producto con mal olor',
      'Producto con hongos, insectos, humedad',
      'Desiste de la garantía',
      'Cambio de patas',
      'Golpes y rayones',
      'Enfermedad en madera',
      'Descosidos'
    ]
  }.freeze

  # correo del area (6 procesos) + plazos del criterio 6 de CAT-01. El PDF
  # habla de 7 procesos: el septimo esta pendiente de confirmacion.
  PROCESOS_GARANTIA = [
    { nombre: 'Visita técnica', codigo: 'visita_tecnica', plazo_dias_habiles: 8 },
    { nombre: 'Recolección', codigo: 'recoleccion', plazo_dias_habiles: 15 },
    { nombre: 'Cambio de producto', codigo: 'cambio_producto', plazo_dias_habiles: 20 },
    { nombre: 'Reparación en fábrica', codigo: 'reparacion_fabrica' },
    { nombre: 'Entrega de producto', codigo: 'entrega_producto' },
    { nombre: 'Devolución de dinero', codigo: 'devolucion_dinero' }
  ].freeze

  # las 10 ciudades con tienda; con tecnico propio solo las 4 confirmadas por
  # el area (correo 04/08). origen_ruta queda null hasta que operaciones lo
  # entregue.
  CIUDADES = %w[Armenia Manizales Pereira Cali Bogotá Ibagué Palmira Popayán Neiva Buenaventura].freeze
  CIUDADES_CON_TECNICO = %w[Armenia Manizales Pereira Cali].freeze

  def initialize(account)
    @account = account
  end

  def sembrar!
    sembrar_simple(Helic3::Catalogo::Categoria, CATEGORIAS)
    sembrar_simple(Helic3::Catalogo::Tipo, TIPOS)
    sembrar_simple(Helic3::Catalogo::EtapaPqr, ETAPAS_PQR)
    sembrar_motivos_garantia
    sembrar_detalles
    sembrar_con_atributos(Helic3::Catalogo::ProcesoGarantia, PROCESOS_GARANTIA)
    sembrar_coberturas
    resumen
  end

  private

  def sembrar_simple(modelo, nombres)
    nombres.each_with_index do |nombre, indice|
      sembrar_fila(modelo, codigo_de(nombre), nombre: nombre, posicion: indice)
    end
  end

  def sembrar_con_atributos(modelo, filas)
    filas.each_with_index do |fila, indice|
      atributos = fila.except(:codigo).merge(posicion: indice)
      sembrar_fila(modelo, fila[:codigo], atributos)
    end
  end

  def sembrar_motivos_garantia
    sembrar_con_atributos(Helic3::Catalogo::MotivoGarantia, MOTIVOS_GARANTIA)
  end

  def sembrar_detalles
    posicion = 0
    DETALLES_POR_MOTIVO.each do |codigo_motivo, nombres|
      motivo = Helic3::Catalogo::MotivoGarantia.find_by!(account: @account, codigo: codigo_motivo)
      nombres.each do |nombre|
        sembrar_fila(Helic3::Catalogo::DetalleTipificado, codigo_de(nombre),
                     nombre: nombre, posicion: posicion, motivo_garantia: motivo)
        posicion += 1
      end
    end
  end

  def sembrar_coberturas
    CIUDADES.each_with_index do |ciudad, indice|
      sembrar_fila(Helic3::Catalogo::CoberturaCiudad, codigo_de(ciudad),
                   nombre: ciudad, posicion: indice,
                   tecnico_propio: CIUDADES_CON_TECNICO.include?(ciudad))
    end
  end

  def sembrar_fila(modelo, codigo, atributos)
    fila = modelo.find_or_initialize_by(account: @account, codigo: codigo)
    fila.assign_attributes(atributos)
    fila.save!
  end

  def codigo_de(nombre)
    nombre.parameterize(separator: '_')
  end

  def resumen
    {
      categorias: Helic3::Catalogo::Categoria.where(account: @account).count,
      tipos: Helic3::Catalogo::Tipo.where(account: @account).count,
      etapas_pqr: Helic3::Catalogo::EtapaPqr.where(account: @account).count,
      motivos_garantia: Helic3::Catalogo::MotivoGarantia.where(account: @account).count,
      detalles_tipificados: Helic3::Catalogo::DetalleTipificado.where(account: @account).count,
      procesos_garantia: Helic3::Catalogo::ProcesoGarantia.where(account: @account).count,
      coberturas_ciudad: Helic3::Catalogo::CoberturaCiudad.where(account: @account).count
    }
  end
end
