# IND-06: Devolucion como expediente hermano de Garantia (mismo patron de
# GAR-01) -- un unico radicado con un reloj de 30 dias habiles, aunque el
# cliente devuelva varios productos; cada producto (item) lleva su propio
# motivo, detalle y proceso.
#
# El consecutivo usa el mismo patron de secuencia por cuenta y trigger que
# Garantia (20260828130000): arranca en la semilla configurada en parametros
# (radicado_devolucion_inicio) si existe, o en 1.
#
# Solo crea tablas propias helic3_*; ninguna tabla upstream se altera.
class CreaDevolucionesConItems < ActiveRecord::Migration[7.2]
  def up
    crear_tabla_devoluciones
    crear_tabla_items
    crear_trigger_consecutivo
  end

  def down
    drop_trigger('helic3_devoluciones_before_insert_row_tr', 'helic3_devoluciones', generated: true)
    drop_table :helic3_devolucion_items
    drop_table :helic3_devoluciones
    borrar_secuencias
  end

  private

  def crear_tabla_devoluciones
    create_table :helic3_devoluciones do |t|
      t.bigint :account_id, null: false
      t.bigint :ticket_id, null: false
      t.integer :display_id, null: false
      t.datetime :abierta_at, null: false
      t.datetime :cerrada_at
      t.integer :presupuesto_dias_habiles
      t.bigint :cobertura_ciudad_id

      t.timestamps
    end

    add_index :helic3_devoluciones, [:account_id, :display_id], unique: true, name: 'idx_h3_devoluciones_account_dpid'
    add_index :helic3_devoluciones, :account_id, name: 'idx_h3_devoluciones_account'
    add_index :helic3_devoluciones, :ticket_id, name: 'idx_h3_devoluciones_ticket'
    add_index :helic3_devoluciones, :cobertura_ciudad_id, name: 'idx_h3_devoluciones_cobertura'
    add_foreign_key :helic3_devoluciones, :helic3_tickets, column: :ticket_id
    add_foreign_key :helic3_devoluciones, :helic3_catalogo_coberturas_ciudad, column: :cobertura_ciudad_id
  end

  # detalle_tipificado_id/proceso_id apuntan a los catalogos YA existentes de
  # Garantia (mismo vocabulario real, confirmado contra el historico) -- ver
  # la migracion de catalogos (20261019190000) para el porque.
  def crear_tabla_items
    create_table :helic3_devolucion_items do |t|
      t.bigint :account_id, null: false
      t.bigint :devolucion_id, null: false
      t.string :producto_nombre, null: false
      t.string :producto_referencia
      t.bigint :motivo_devolucion_id
      t.bigint :detalle_tipificado_id
      t.bigint :proceso_id
      t.datetime :resuelto_at
      t.string :decision

      t.timestamps
    end

    add_index :helic3_devolucion_items, :account_id, name: 'idx_h3_ditems_account'
    add_index :helic3_devolucion_items, :devolucion_id, name: 'idx_h3_ditems_devolucion'
    add_index :helic3_devolucion_items, :proceso_id, name: 'idx_h3_ditems_proceso'
    add_index :helic3_devolucion_items, :motivo_devolucion_id, name: 'idx_h3_ditems_motivo'
    add_index :helic3_devolucion_items, :detalle_tipificado_id, name: 'idx_h3_ditems_detalle'
    fks_items
  end

  def fks_items
    add_foreign_key :helic3_devolucion_items, :helic3_devoluciones, column: :devolucion_id
    add_foreign_key :helic3_devolucion_items, :helic3_catalogo_motivos_devolucion, column: :motivo_devolucion_id
    add_foreign_key :helic3_devolucion_items, :helic3_catalogo_detalles_tipificados, column: :detalle_tipificado_id
    add_foreign_key :helic3_devolucion_items, :helic3_catalogo_procesos_garantia, column: :proceso_id
  end

  def crear_trigger_consecutivo
    create_trigger('helic3_devoluciones_before_insert_row_tr', generated: true, compatibility: 1)
      .on('helic3_devoluciones')
      .before(:insert)
      .for_each(:row) do
      <<~SQL.squish
        EXECUTE format('CREATE SEQUENCE IF NOT EXISTS helic3_devolucion_dpid_seq_%s START WITH %s',
                       NEW.account_id,
                       COALESCE((SELECT valor::integer FROM helic3_catalogo_parametros
                                 WHERE account_id = NEW.account_id
                                   AND clave = 'radicado_devolucion_inicio'), 1));
        NEW.display_id := nextval('helic3_devolucion_dpid_seq_' || NEW.account_id);
      SQL
    end
  end

  def borrar_secuencias
    execute <<~SQL.squish
      DO $$
      DECLARE seq_record RECORD;
      BEGIN
        FOR seq_record IN SELECT sequencename FROM pg_sequences WHERE sequencename LIKE 'helic3_devolucion_dpid_seq_%' LOOP
          EXECUTE format('DROP SEQUENCE IF EXISTS %I', seq_record.sequencename);
        END LOOP;
      END $$;
    SQL
  end
end
