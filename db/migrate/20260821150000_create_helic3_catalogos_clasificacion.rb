# CAT-01: catalogos de clasificacion parametrizables del modulo de PQR y
# Garantias. La clasificacion vive como datos administrables, no en el prompt
# del agente ni en constantes: un ajuste del area es una fila, no un deploy.
#
# Todos los indices llevan nombre corto explicito (idx_h3cat_*): varios de
# los generados por Rails superarian el limite de 63 caracteres de Postgres.
class CreateHelic3CatalogosClasificacion < ActiveRecord::Migration[7.2]
  def change
    crear_catalogos_de_pqr
    crear_catalogos_de_garantia
  end

  private

  def crear_catalogos_de_pqr
    # clasificacion de primer nivel: activa el flujo de atencion
    crear_catalogo :helic3_catalogo_categorias

    # la P, la Q y la R: define el plazo legal de respuesta
    crear_catalogo :helic3_catalogo_tipos do |t|
      t.integer :plazo_dias_habiles
    end

    # que esta pidiendo el cliente; decide si el caso abre garantia
    crear_catalogo :helic3_catalogo_motivos_pqr do |t|
      t.references :categoria, null: false,
                               foreign_key: { to_table: :helic3_catalogo_categorias },
                               index: { name: 'idx_h3cat_motivos_pqr_categoria' }
      t.boolean :abre_garantia, null: false, default: false
    end

    # con que se cierra el tramite
    crear_catalogo :helic3_catalogo_resultados do |t|
      t.boolean :cierra_pqr, null: false, default: false
      t.boolean :abre_garantia, null: false, default: false
    end

    # el estado con efecto legal, el que ve el cliente
    crear_catalogo :helic3_catalogo_etapas_pqr do |t|
      t.boolean :detiene_reloj, null: false, default: false
      t.boolean :visible_cliente, null: false, default: true
    end
  end

  def crear_catalogos_de_garantia
    # que paso con el producto, asignado por regla parametrizada en dias
    crear_catalogo :helic3_catalogo_motivos_garantia do |t|
      t.string :regla
      t.integer :parametro_dias
    end

    # la falla fisica concreta del producto; nunca sin su motivo (criterio 3)
    crear_catalogo :helic3_catalogo_detalles_tipificados do |t|
      t.references :motivo_garantia, null: false,
                                     foreign_key: { to_table: :helic3_catalogo_motivos_garantia },
                                     index: { name: 'idx_h3cat_detalles_motivo' }
    end

    # el estado operativo interno de la garantia, cada uno con su plazo propio
    crear_catalogo :helic3_catalogo_procesos_garantia do |t|
      t.integer :plazo_dias_habiles
    end

    # si la ciudad tiene tecnico propio y por donde arranca la ruta
    crear_catalogo :helic3_catalogo_coberturas_ciudad do |t|
      t.boolean :tecnico_propio, null: false, default: false
      t.string :origen_ruta
    end
  end

  # campos comunes de todo catalogo: nombre, codigo, posicion, activo y cuenta
  # (criterio 2). El codigo es unico por cuenta (criterio 3).
  def crear_catalogo(tabla)
    corto = tabla.to_s.delete_prefix('helic3_catalogo_')
    create_table tabla do |t|
      t.references :account, null: false, index: { name: "idx_h3cat_#{corto}_account" }
      t.string :nombre, null: false
      t.string :codigo, null: false
      t.integer :posicion, null: false, default: 0
      t.boolean :activo, null: false, default: true

      yield t if block_given?

      t.timestamps
    end
    add_index tabla, [:account_id, :codigo], unique: true, name: "idx_h3cat_#{corto}_account_codigo"
  end
end
