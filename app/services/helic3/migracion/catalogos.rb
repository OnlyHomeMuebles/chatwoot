# frozen_string_literal: true

# MIG-02 (Pieza 2, mapeo): traduce los NOMBRES del DataGrid a los objetos de
# catálogo de Helic3, con los mapas de MIG-01 (Tablas 4 y 5), y hace la validación
# previa a simular: lista qué catálogos faltan para que la página no deje simular
# sin ellos (CA). Un valor presente que no mapea a un catálogo existente se reporta;
# nunca se crea catálogo ni se deja el campo vacío en silencio.
class Helic3::Migracion::Catalogos
  # Proceso del ítem cuando la garantía está ABIERTA (Tabla 4). En una cerrada el
  # proceso es garantia_finalizada (o garantia_negada), sin importar este valor.
  PROCESOS_ABIERTAS = {
    'cambio producto' => 'cambio_producto',
    'visita tecnica' => 'visita_tecnica',
    'recoleccion' => 'recoleccion',
    'ruta en fabrica' => 'reparacion_fabrica',
    'entrega producto' => 'entrega_producto',
    'devolucion de dinero' => 'devolucion_dinero',
    'derecho de peticion' => 'derecho_peticion'
  }.freeze
  PROCESO_CERRADA = 'garantia_finalizada'
  PROCESO_NEGADA = 'garantia_negada'

  # Motivo de garantía (Tabla 5). El "--" ya lo pasó el lector a Calidad.
  MOTIVOS = {
    'calidad - producto comprado' => 'calidad_producto_comprado',
    'reparacion - primera entrega' => 'reparacion_primera_entrega',
    'devoluciones - primera entrega' => 'devoluciones_primera_entrega',
    'error de pedido - tienda' => 'error_pedido_tienda',
    'error de pedido - logistica' => 'error_pedido_logistica',
    'derecho de retracto' => 'derecho_de_retracto'
  }.freeze

  ETAPAS_ABIERTAS = ['en gestion', 'nuevo'].freeze

  # catálogos fijos que todo caso usa: [clase, código].
  FIJOS = {
    tipo: [Helic3::Catalogo::Tipo, 'garantia'],
    etapa: [Helic3::Catalogo::EtapaPqr, 'solucionado'],
    resultado: [Helic3::Catalogo::Resultado, 'procede_garantia'],
    motivo_pqr: [Helic3::Catalogo::MotivoPqr, 'garantia_producto']
  }.freeze

  NOMBRE_RESPONSABLE = 'experiencia al cliente'

  def initialize(account:)
    @account = account
    @procesos   = indexar(Helic3::Catalogo::ProcesoGarantia, :codigo)
    @motivos    = indexar(Helic3::Catalogo::MotivoGarantia, :codigo)
    @detalles   = indexar(Helic3::Catalogo::DetalleTipificado, :nombre, norm: true)
    @coberturas = indexar(Helic3::Catalogo::CoberturaCiudad, :nombre, norm: true)
  end

  def abierta?(caso)
    ETAPAS_ABIERTAS.include?(normalizar(caso[:etapa_caso]))
  end

  # código de proceso del ítem según la Tabla 4; nil si la columna no mapea (p.ej.
  # un caso abierto con proceso vacío queda sin proceso, que el modelo permite).
  def codigo_proceso(caso)
    if abierta?(caso)
      PROCESOS_ABIERTAS[normalizar(caso[:proceso])]
    elsif normalizar(caso[:proceso]) == 'garantia negada'
      PROCESO_NEGADA
    else
      PROCESO_CERRADA
    end
  end

  def proceso_para(caso)
    codigo = codigo_proceso(caso)
    codigo && @procesos[codigo]
  end

  def motivo_para(caso)
    codigo = MOTIVOS[normalizar(caso[:motivo])]
    codigo && @motivos[codigo]
  end

  def detalle_para(nombre)
    return nil if nombre.blank?

    @detalles[normalizar(nombre)]
  end

  def cobertura_para(ciudad)
    return nil if ciudad.blank?

    @coberturas[normalizar(ciudad).gsub(/,? *d\.c\.?/, '').strip]
  end

  def responsable
    @responsable ||= @account.users.find_by('LOWER(name) = ?', NOMBRE_RESPONSABLE)
  end

  FIJOS.each_key do |nombre|
    define_method(nombre) { fijo(nombre) }
  end

  # Validación pre-vuelo (CA): lista textual de lo que falta para poder simular.
  # Vacía = todo está. Revisa fijos, el agente, y cada proceso/motivo/detalle que
  # los casos necesitan pero que el catálogo no tiene.
  def faltantes(casos)
    faltas = []
    FIJOS.each { |nombre, (clase, codigo)| faltas << "#{clase.name.demodulize} '#{codigo}'" if fijo(nombre).nil? }
    faltas << "usuario '#{NOMBRE_RESPONSABLE}'" if responsable.nil?

    procesos, motivos, detalles = recolectar(casos)
    faltas.concat(procesos.reject { |c| @procesos.key?(c) }.map { |c| "proceso '#{c}'" })
    faltas.concat(motivos.reject { |c| @motivos.key?(c) }.map { |c| "motivo de garantía '#{c}'" })
    faltas.concat(detalles.reject { |n| @detalles.key?(normalizar(n)) }.map { |n| "detalle tipificado '#{n}'" })
    faltas.uniq
  end

  private

  # junta los códigos de proceso/motivo y los nombres de detalle que aparecen en los
  # casos (solo los no vacíos), para verificar cuáles no están sembrados.
  def recolectar(casos)
    procesos = casos.filter_map { |caso| codigo_proceso(caso) }.uniq
    motivos  = casos.filter_map { |caso| MOTIVOS[normalizar(caso[:motivo])] }.uniq
    detalles = casos.flat_map { |caso| caso[:productos].map { |p| p[:detalle] } }.compact.uniq
    [procesos, motivos, detalles]
  end

  def fijo(nombre)
    @fijos ||= {}
    @fijos.fetch(nombre) do
      clase, codigo = FIJOS[nombre]
      @fijos[nombre] = clase.find_by(account: @account, codigo: codigo)
    end
  end

  def indexar(clase, campo, norm: false)
    clase.where(account: @account).activos.index_by do |fila|
      valor = fila.public_send(campo)
      norm ? normalizar(valor) : valor.to_s.strip
    end
  end

  def normalizar(texto)
    texto.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.strip.gsub(/\s+/, ' ')
  end
end
