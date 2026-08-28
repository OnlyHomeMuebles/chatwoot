# GAR-01: una solicitud de garantia se maneja con UN unico numero de radicado
# aunque el cliente reporte varios productos, y cada producto (item) lleva por
# dentro su propio motivo, detalle y estado, para seguimiento individual sin
# radicaciones duplicadas (decision de Only Home del 25/08).
#
# El consecutivo usa el mismo patron de secuencia por cuenta y trigger que el
# expediente, con una diferencia: la secuencia se crea al primer uso y arranca
# en la semilla configurada en parametros (radicado_garantia_inicio), porque
# Only Home aun no decide si continua el consecutivo actual o arranca uno
# nuevo (atado a la migracion de historico, diferida).
#
# Solo crea tablas propias helic3_*; ninguna tabla upstream se altera.
class CreaGarantiasConItems < ActiveRecord::Migration[7.2]
  def up
    crear_tabla_garantias
    crear_tabla_items
    crear_trigger_consecutivo
  end

  def down
    drop_trigger('helic3_garantias_before_insert_row_tr', 'helic3_garantias', generated: true)
    drop_table :helic3_garantia_items
    drop_table :helic3_garantias
    borrar_secuencias
  end

  private

  def crear_tabla_garantias
    create_table :helic3_garantias do |t|
      t.bigint :account_id, null: false
      t.bigint :ticket_id, null: false
      t.integer :display_id, null: false
      # una sola fecha de apertura para TODO el radicado (un solo reloj);
      # el presupuesto de dias se copia del parametro al crear, para que un
      # cambio posterior del parametro no mueva las garantias ya abiertas
      t.datetime :abierta_at, null: false
      t.datetime :cerrada_at
      t.integer :presupuesto_dias_habiles
      t.bigint :cobertura_ciudad_id

      t.timestamps
    end

    add_index :helic3_garantias, [:account_id, :display_id], unique: true, name: 'idx_h3_garantias_account_dpid'
    add_index :helic3_garantias, :account_id, name: 'idx_h3_garantias_account'
    add_index :helic3_garantias, :ticket_id, name: 'idx_h3_garantias_ticket'
    add_index :helic3_garantias, :cobertura_ciudad_id, name: 'idx_h3_garantias_cobertura'
    add_foreign_key :helic3_garantias, :helic3_tickets, column: :ticket_id
    add_foreign_key :helic3_garantias, :helic3_catalogo_coberturas_ciudad, column: :cobertura_ciudad_id
  end

  def crear_tabla_items
    create_table :helic3_garantia_items do |t|
      t.bigint :account_id, null: false
      t.bigint :garantia_id, null: false
      t.string :producto_nombre, null: false
      t.string :producto_referencia
      # la clasificacion del producto vive en el ITEM, nunca en la garantia
      # (punto donde el modelo se separa de como se hacia antes, deliberado)
      t.bigint :motivo_garantia_id
      t.bigint :detalle_tipificado_id
      t.bigint :proceso_id
      t.datetime :resuelto_at
      t.string :decision

      t.timestamps
    end

    add_index :helic3_garantia_items, :account_id, name: 'idx_h3_gitems_account'
    add_index :helic3_garantia_items, :garantia_id, name: 'idx_h3_gitems_garantia'
    add_index :helic3_garantia_items, :proceso_id, name: 'idx_h3_gitems_proceso'
    add_index :helic3_garantia_items, :motivo_garantia_id, name: 'idx_h3_gitems_motivo'
    add_index :helic3_garantia_items, :detalle_tipificado_id, name: 'idx_h3_gitems_detalle'
    add_foreign_key :helic3_garantia_items, :helic3_garantias, column: :garantia_id
    add_foreign_key :helic3_garantia_items, :helic3_catalogo_motivos_garantia, column: :motivo_garantia_id
    add_foreign_key :helic3_garantia_items, :helic3_catalogo_detalles_tipificados, column: :detalle_tipificado_id
    add_foreign_key :helic3_garantia_items, :helic3_catalogo_procesos_garantia, column: :proceso_id
  end

  def crear_trigger_consecutivo
    create_trigger('helic3_garantias_before_insert_row_tr', generated: true, compatibility: 1)
      .on('helic3_garantias')
      .before(:insert)
      .for_each(:row) do
      <<~SQL.squish
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS helic3_garantia_dpid_seq_%s START WITH %s',
                       NEW.account_id,
                       COALESCE((SELECT valor::integer FROM helic3_catalogo_parametros
                                 WHERE account_id = NEW.account_id
                                   AND clave = 'radicado_garantia_inicio'), 1));
        NEW.display_id := nextval('helic3_garantia_dpid_seq_' || NEW.account_id);
      SQL
    end
  end

  def borrar_secuencias
    execute <<~SQL.squish
      DO $$
      DECLARE seq_record RECORD;
      BEGIN
        FOR seq_record IN SELECT sequencename FROM pg_sequences WHERE sequencename LIKE 'helic3_garantia_dpid_seq_%' LOOP
          EXECUTE format('DROP SEQUENCE IF EXISTS %I', seq_record.sequencename);
        END LOOP;
      END $$;
    SQL
  end
end
