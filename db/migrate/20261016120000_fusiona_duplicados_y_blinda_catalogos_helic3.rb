# frozen_string_literal: true

# Segunda parte del saneamiento de codigos de catalogo (continua la del #127).
#
# La migracion anterior (20261015120000) normalizo los codigos, pero cuando un
# codigo limpio chocaba con otra fila de la misma cuenta NO fusiono el duplicado:
# lo dejo sucio y lo reporto, porque fusionar sin re-apuntar sus referencias
# perderia datos (tickets, ficha, garantia_items).
#
# Esta migracion salda esa deuda y blinda la base:
#   1. Fusiona los duplicados que queden: por cada grupo que colapsa al mismo
#      (cuenta, codigo), elige una superviviente, RE-APUNTA todas las FKs que
#      apuntaban a las demas y recien entonces las borra. De paso normaliza
#      cualquier codigo aun sucio, para no depender de que la 1a haya corrido.
#   2. Agrega un CHECK en cada tabla de catalogo para que un codigo mal formado
#      (con espacios/mayusculas) no pueda volver a entrar NI POR SQL DIRECTO, que
#      es justamente como entro el "nueva " que rompio la radicacion en prod.
#
# Es irreversible: una fila borrada y el espacio original de un codigo no se
# pueden reconstruir.
class FusionaDuplicadosYBlindaCatalogosHelic3 < ActiveRecord::Migration[7.2]
  # Los 10 catalogos con columna `codigo` (los mismos que normalizo la 1a). Se
  # recorren con su modelo para agrupar filas y con su table_name para ubicar sus
  # referencias en REFERENCIAS.
  MODELOS = %w[
    Categoria Tipo EtapaPqr MotivoPqr Resultado
    MotivoGarantia DetalleTipificado ProcesoGarantia CoberturaCiudad Formato
  ].freeze

  # Cada tabla de catalogo -> las [tabla, columna] que la referencian por FK.
  # Tomado del schema (add_foreign_key ... -> helic3_catalogo_*). Es el grafo que
  # hay que re-apuntar antes de borrar una fila duplicada.
  REFERENCIAS = {
    'helic3_catalogo_categorias' => [
      %w[helic3_catalogo_motivos_pqr categoria_id],
      %w[helic3_tickets categoria_id]
    ],
    'helic3_catalogo_tipos' => [
      %w[helic3_tickets tipo_id]
    ],
    'helic3_catalogo_etapas_pqr' => [
      %w[helic3_tickets etapa_id]
    ],
    'helic3_catalogo_motivos_pqr' => [
      %w[helic3_tickets motivo_pqr_id]
    ],
    'helic3_catalogo_resultados' => [
      %w[helic3_tickets resultado_id]
    ],
    'helic3_catalogo_motivos_garantia' => [
      %w[helic3_catalogo_detalles_tipificados motivo_garantia_id],
      %w[helic3_garantia_items motivo_garantia_id]
    ],
    'helic3_catalogo_detalles_tipificados' => [
      %w[helic3_garantia_items detalle_tipificado_id],
      %w[helic3_ticket_datos detalle_tipificado_id]
    ],
    'helic3_catalogo_procesos_garantia' => [
      %w[helic3_garantia_items proceso_id]
    ],
    'helic3_catalogo_coberturas_ciudad' => [
      %w[helic3_garantias cobertura_ciudad_id]
    ],
    'helic3_catalogo_formatos' => [
      %w[helic3_catalogo_procesos_garantia formato_sugerido_id],
      %w[helic3_plantillas_formato formato_id]
    ]
  }.freeze

  FORMATO_SLUG = '^[a-z0-9_]+$'

  def up
    tablas_limpias = fusionar_duplicados
    blindar_codigos(tablas_limpias)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'No se puede resucitar una fila fusionada ni el espacio original de un codigo.'
  end

  private

  # Devuelve los nombres de tabla que quedaron 100% limpios (aptos para el CHECK).
  # Una tabla donde algun grupo no se pudo sanear queda fuera: se blinda a mano.
  #
  # Nota (deuda asumida): se recorre con los modelos vivos (constantize + .all).
  # Es el mismo patron que la 1a migracion y mantiene el codigo legible; el riesgo
  # (que un modelo se renombre y rompa el replay) es bajo para catalogos estables.
  def fusionar_duplicados
    MODELOS.filter_map do |nombre|
      modelo = "Helic3::Catalogo::#{nombre}".constantize
      modelo.reset_column_information
      fusionar_catalogo(modelo) ? modelo.table_name : nil
    end
  end

  # Agrupa por (cuenta, codigo normalizado) y sanea cada grupo. Devuelve true solo
  # si TODOS los grupos quedaron limpios; si alguno fallo, false (la tabla no se
  # blindara). Una sola fila sin duplicado tambien pasa por aqui y se limpia.
  def fusionar_catalogo(modelo)
    modelo.all.group_by { |fila| [fila.account_id, slug(fila.codigo)] }.values.map do |filas|
      sanear_grupo(modelo.table_name, filas)
    end.all?
  end

  # Fusiona un grupo dentro de un SAVEPOINT: si re-apuntar choca con un indice
  # unico del referenciante (p. ej. dos plantillas del mismo formato con igual
  # version), se revierte SOLO este grupo y se reporta, sin abortar la migracion.
  def sanear_grupo(tabla, filas)
    superviviente = elegir_superviviente(filas)
    codigo_limpio = slug(superviviente.codigo)
    return reportar_sin_slug(tabla, superviviente) if codigo_limpio.empty?

    ActiveRecord::Base.transaction(requires_new: true) do
      (filas - [superviviente]).each { |dup| absorber(tabla, dup, superviviente) }
      superviviente.update_columns(codigo: codigo_limpio) if superviviente.codigo != codigo_limpio
    end
    true
  rescue ActiveRecord::StatementInvalid => e
    say "NO FUSIONADO #{tabla} (cuenta #{filas.first.account_id}, '#{codigo_limpio}'): " \
        "#{e.message.lines.first.to_s.strip}. Revisar a mano; la tabla no se blinda aun."
    false
  end

  # Re-apunta TODAS las referencias de la fila duplicada a la superviviente y
  # recien entonces la borra. El orden importa: las FK son RESTRICT, asi que la
  # base no deja borrar una fila referenciada; re-apuntar primero es obligatorio.
  def absorber(tabla, dup, superviviente)
    (REFERENCIAS[tabla] || []).each do |ref_tabla, columna|
      execute(
        "UPDATE #{ref_tabla} SET #{columna} = #{superviviente.id} WHERE #{columna} = #{dup.id}"
      )
    end
    say "FUSIONADO #{tabla} id=#{dup.id} ('#{dup.codigo}') -> id=#{superviviente.id} ('#{superviviente.codigo}')"
    dup.delete
  end

  # Un codigo que queda vacio al normalizar (p. ej. '...') no es un slug valido y
  # haria fallar el CHECK (^[a-z0-9_]+$ exige >=1 caracter): no se toca, se reporta.
  def reportar_sin_slug(tabla, fila)
    say "SIN SLUG #{tabla} id=#{fila.id} ('#{fila.codigo}'): el codigo queda vacio al " \
        'normalizar. Revisar a mano; la tabla no se blinda aun.'
    false
  end

  # Gana la fila que YA tiene el codigo limpio (la que la 1a respeto); si ninguna,
  # la de menor id. Determinista: mismo resultado en test y en produccion.
  def elegir_superviviente(filas)
    filas.min_by { |fila| [fila.codigo == slug(fila.codigo) ? 0 : 1, fila.id] }
  end

  def slug(codigo)
    codigo.to_s.strip.parameterize(separator: '_')
  end

  # Barrera estructural: ni un INSERT por SQL directo puede volver a meter un
  # codigo con espacios o mayusculas. Solo blinda las tablas que quedaron limpias.
  # Idempotente: no re-agrega el CHECK si ya existe (el spec reejecuta up).
  def blindar_codigos(tablas_limpias)
    MODELOS.each do |nombre|
      tabla = "Helic3::Catalogo::#{nombre}".constantize.table_name
      next unless tablas_limpias.include?(tabla)

      constraint = "#{tabla}_codigo_slug"
      next if connection.check_constraints(tabla).any? { |c| c.name == constraint }

      add_check_constraint tabla, "codigo ~ '#{FORMATO_SLUG}'", name: constraint
    end
  end
end
