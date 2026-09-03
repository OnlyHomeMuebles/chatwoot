# Siembra los catalogos de clasificacion (CAT-01) y su cierre (CAT-02) con
# los valores del diseno validado con Only Home (asignacion del 21/08 y
# addendum del 24/08) y del correo del area del 04/08.
#
# Idempotente y respetuosa (criterio 7 de CAT-02): la llave natural es el
# codigo/clave por cuenta; si la fila YA existe, la semilla NO la toca — las
# ediciones hechas por consola son fuente de verdad despues de la creacion.
# El indice unico de cada tabla es la red de seguridad final.
#
# Los nombres del correo se conservan LITERALES como los escribio el area
# (incluidas posibles erratas como "Chapilla leventada"): corregirlos sin
# confirmacion seria resolver por cuenta propia.
#
# Lo que sigue sin confirmar esta en app/models/helic3/catalogo/PENDIENTES.md.
class Helic3::Catalogo::SeederService
  # codigos explicitos (no derivados del nombre): los motivos de PQR los
  # referencian, y un ajuste de redaccion del nombre no debe romper la semilla
  CATEGORIAS = [
    { nombre: 'Garantía', codigo: 'garantia' },
    { nombre: 'Servicio', codigo: 'servicio' },
    { nombre: 'Comercial', codigo: 'comercial' },
    { nombre: 'Logística', codigo: 'logistica' },
    { nombre: 'Facturación', codigo: 'facturacion' },
    # Informacion no genera radicado ni plazo (EXP-01): el expediente se crea
    # para conservar historial, sin numero visible y fuera del conteo SIC.
    { nombre: 'Información', codigo: 'informacion', genera_radicado: false }
  ].freeze

  # plazo legal por tipo (addendum 24/08): P, Q y R responden en 15 dias
  # habiles; sugerencia y felicitacion no tienen plazo legal (null a proposito)
  TIPOS = [
    { nombre: 'Petición', codigo: 'peticion', plazo_dias_habiles: 15 },
    { nombre: 'Queja', codigo: 'queja', plazo_dias_habiles: 15 },
    { nombre: 'Reclamo', codigo: 'reclamo', plazo_dias_habiles: 15 },
    { nombre: 'Sugerencia', codigo: 'sugerencia' },
    { nombre: 'Felicitación', codigo: 'felicitacion' }
  ].freeze

  # el reloj legal (addendum 24/08): la PQR se resuelve cuando se INFORMA al
  # cliente que procede, no cuando el producto queda arreglado. Solo
  # "Respondida" detiene el reloj. Todas visibles al cliente.
  ETAPAS_PQR = [
    { nombre: 'Nueva', codigo: 'nueva' },
    { nombre: 'En análisis', codigo: 'en_analisis' },
    { nombre: 'Respondida', codigo: 'respondida', detiene_reloj: true },
    { nombre: 'Cerrada', codigo: 'cerrada' }
  ].freeze

  # los 7 motivos de PQR del diseno validado (addendum 24/08), con su
  # categoria, su politica de apertura de garantia y su plazo propio
  MOTIVOS_PQR = [
    { nombre: 'Garantía de producto', codigo: 'garantia_producto',
      categoria: 'garantia', abre_garantia: :siempre },
    { nombre: 'Error de despacho o entrega incompleta', codigo: 'error_despacho_entrega',
      categoria: 'logistica', abre_garantia: :segun_analisis },
    { nombre: 'Retracto de compra', codigo: 'retracto_compra',
      categoria: 'comercial', abre_garantia: :nunca, plazo_dias_habiles: 5 },
    { nombre: 'Estado del pedido o demora en la entrega', codigo: 'estado_pedido_demora',
      categoria: 'logistica', abre_garantia: :nunca },
    { nombre: 'Facturación o cobro', codigo: 'facturacion_cobro',
      categoria: 'facturacion', abre_garantia: :nunca },
    { nombre: 'Atención y asesoría en la venta', codigo: 'atencion_asesoria_venta',
      categoria: 'servicio', abre_garantia: :nunca },
    { nombre: 'Información de productos, tiendas u horarios', codigo: 'informacion_general',
      categoria: 'informacion', abre_garantia: :nunca }
  ].freeze

  # los 7 resultados del diseno validado (addendum 24/08). aprobacion_humana:
  # negar una garantia o aprobar un retracto (mueve dinero) exige persona
  RESULTADOS = [
    { nombre: 'Procede garantía', codigo: 'procede_garantia', cierra_pqr: true, abre_garantia: true },
    { nombre: 'No procede garantía', codigo: 'no_procede_garantia', cierra_pqr: true, aprobacion_humana: true },
    { nombre: 'Resuelta con información', codigo: 'resuelta_informacion', cierra_pqr: true },
    { nombre: 'Resuelta con cambio directo', codigo: 'resuelta_cambio_directo', cierra_pqr: true },
    { nombre: 'Retracto aprobado', codigo: 'retracto_aprobado', cierra_pqr: true, aprobacion_humana: true },
    { nombre: 'Desistimiento del cliente', codigo: 'desistimiento_cliente', cierra_pqr: true },
    { nombre: 'Trasladada a otra área', codigo: 'trasladada_otra_area' }
  ].freeze

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

  # 31 detalles literales del correo. Catalogo AUTONOMO desde CAT-02 (frente
  # A): sin motivo asociado — el motivo lo decide la regla de fecha, no el
  # detalle. El PDF de asignacion hablaba de 28 detalles "acordados con
  # produccion": la diferencia con estos 31 sigue pendiente de conciliar.
  DETALLES_TIPIFICADOS = [
    'Referencia diferente a la solicitada', 'Referencia incorrecta', 'Falta de asesoría en la venta',
    'Producto roto en entrega', 'Entrega parcial', 'Falta de piezas o manuales', 'Entrega fuera de plazo',
    'Producto inestable / cojo', 'Producto desajustado', 'Producto fracturado o roto', 'Producto dilatado',
    'Herraje oxidado o defectuoso', 'Producto mal pintado', 'Chapilla leventada', 'Baja densidad de espuma',
    'Tela destemplada', 'Falla en acabados o alineación', 'Producto rayado', 'Producto sucio',
    'Variación en el tono', 'Tonos diferentes entre productos', 'Productos decolorado', 'Tela motosa',
    'Tela o madera diferente', 'Producto con mal olor', 'Producto con hongos, insectos, humedad',
    'Desiste de la garantía', 'Cambio de patas', 'Golpes y rayones', 'Enfermedad en madera', 'Descosidos'
  ].freeze

  # los 7 estados de producto de la maquina de estados (insumos del Sprint 3,
  # lista del 19/08): el septimo es "Garantía negada", terminal desde el
  # dictamen. Terminales = entrega, devolucion de dinero y garantia negada
  # (el cambio de producto NO es terminal: termina en la entrega). El plazo
  # de "Reparación en fábrica" es dinamico (= saldo del presupuesto), por
  # eso queda null: lo resuelve PLZ-01.
  PROCESOS_GARANTIA = [
    { nombre: 'Visita técnica', codigo: 'visita_tecnica', plazo_dias_habiles: 8 },
    { nombre: 'Recolección', codigo: 'recoleccion', plazo_dias_habiles: 15 },
    { nombre: 'Reparación en fábrica', codigo: 'reparacion_fabrica' },
    { nombre: 'Cambio de producto', codigo: 'cambio_producto', plazo_dias_habiles: 20 },
    { nombre: 'Entrega de producto', codigo: 'entrega_producto', es_terminal: true },
    { nombre: 'Devolución de dinero', codigo: 'devolucion_dinero', es_terminal: true },
    { nombre: 'Garantía negada', codigo: 'garantia_negada', es_terminal: true }
  ].freeze

  # origen de la ruta (addendum 24/08): con tecnico propio la garantia
  # arranca en visita tecnica; sin tecnico, directo a recoleccion
  CIUDADES = %w[Armenia Manizales Pereira Cali Bogotá Ibagué Palmira Popayán Neiva Buenaventura].freeze
  CIUDADES_CON_TECNICO = %w[Armenia Manizales Pereira Cali].freeze

  # parametros de operacion (addendum 24/08, frente B)
  PARAMETROS = [
    { clave: 'plazo_respuesta_pqr', valor: '15', unidad: 'dias_habiles' },
    { clave: 'plazo_total_garantia', valor: '30', unidad: 'dias_habiles' },
    { clave: 'meta_interna_garantia', valor: '15', unidad: 'dias' },
    { clave: 'plazo_retracto', valor: '5', unidad: 'dias_habiles' },
    { clave: 'amparo_garantia', valor: '12', unidad: 'meses' },
    { clave: 'minimo_visitas_ruta', valor: '5', unidad: 'cantidad' },
    { clave: 'umbral_confianza_agente', valor: '85', unidad: 'porcentaje' },
    { clave: 'exigir_direccion_confirmada', valor: 'true', unidad: 'booleano' },
    { clave: 'mostrar_solo_ticket_garantia', valor: 'true', unidad: 'booleano' },
    # Umbrales del semaforo (PRM-01): los lee Helic3::PresupuestoGarantia via
    # Helic3::ParametrosGarantia. Sin ellos el semaforo no se puede calcular.
    # Garantia y autonomia van con valor definitivo; los de PQR (8 y 3) son
    # propuesta pendiente de confirmar con el tech lead antes de integrar.
    { clave: 'umbral_verde_garantia', valor: '15', unidad: 'dias_habiles' },
    { clave: 'umbral_amarillo_garantia', valor: '5', unidad: 'dias_habiles' },
    { clave: 'umbral_verde_pqr', valor: '8', unidad: 'dias_habiles' },
    { clave: 'umbral_amarillo_pqr', valor: '3', unidad: 'dias_habiles' },
    { clave: 'autonomia_radicar_pqr', valor: 'propone', unidad: 'texto' }
  ].freeze

  def initialize(account)
    @account = account
  end

  def sembrar!
    sembrar_con_atributos(Helic3::Catalogo::Categoria, CATEGORIAS)
    sembrar_con_atributos(Helic3::Catalogo::Tipo, TIPOS)
    sembrar_con_atributos(Helic3::Catalogo::EtapaPqr, ETAPAS_PQR)
    sembrar_motivos_pqr
    sembrar_con_atributos(Helic3::Catalogo::Resultado, RESULTADOS)
    sembrar_con_atributos(Helic3::Catalogo::MotivoGarantia, MOTIVOS_GARANTIA)
    sembrar_simple(Helic3::Catalogo::DetalleTipificado, DETALLES_TIPIFICADOS)
    sembrar_con_atributos(Helic3::Catalogo::ProcesoGarantia, PROCESOS_GARANTIA)
    sembrar_coberturas
    sembrar_parametros
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

  def sembrar_motivos_pqr
    MOTIVOS_PQR.each_with_index do |fila, indice|
      categoria = Helic3::Catalogo::Categoria.find_by!(account: @account, codigo: fila[:categoria])
      atributos = fila.except(:codigo, :categoria).merge(posicion: indice, categoria: categoria)
      sembrar_fila(Helic3::Catalogo::MotivoPqr, fila[:codigo], atributos)
    end
  end

  def sembrar_coberturas
    CIUDADES.each_with_index do |ciudad, indice|
      con_tecnico = CIUDADES_CON_TECNICO.include?(ciudad)
      sembrar_fila(Helic3::Catalogo::CoberturaCiudad, codigo_de(ciudad),
                   nombre: ciudad, posicion: indice, tecnico_propio: con_tecnico,
                   origen_ruta: con_tecnico ? 'visita_tecnica' : 'recoleccion')
    end
  end

  def sembrar_parametros
    PARAMETROS.each do |fila|
      next if Helic3::Catalogo::Parametro.exists?(account: @account, clave: fila[:clave])

      Helic3::Catalogo::Parametro.create!(fila.merge(account: @account))
    end
  end

  # la semilla solo CREA: si la fila ya existe, no la toca (criterio 7 de
  # CAT-02 — las ediciones por consola no se pisan al re-ejecutar)
  def sembrar_fila(modelo, codigo, atributos)
    return if modelo.exists?(account: @account, codigo: codigo)

    modelo.create!(atributos.merge(account: @account, codigo: codigo))
  end

  def codigo_de(nombre)
    nombre.parameterize(separator: '_')
  end

  def resumen
    {
      categorias: Helic3::Catalogo::Categoria.where(account: @account).count,
      tipos: Helic3::Catalogo::Tipo.where(account: @account).count,
      etapas_pqr: Helic3::Catalogo::EtapaPqr.where(account: @account).count,
      motivos_pqr: Helic3::Catalogo::MotivoPqr.where(account: @account).count,
      resultados: Helic3::Catalogo::Resultado.where(account: @account).count,
      motivos_garantia: Helic3::Catalogo::MotivoGarantia.where(account: @account).count,
      detalles_tipificados: Helic3::Catalogo::DetalleTipificado.where(account: @account).count,
      procesos_garantia: Helic3::Catalogo::ProcesoGarantia.where(account: @account).count,
      coberturas_ciudad: Helic3::Catalogo::CoberturaCiudad.where(account: @account).count,
      parametros: Helic3::Catalogo::Parametro.where(account: @account).count
    }
  end
end
