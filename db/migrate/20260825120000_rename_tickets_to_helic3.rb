class RenameTicketsToHelic3 < ActiveRecord::Migration[7.2]
  # Mueve la tabla tickets al namespace Helic3::Ticket (helic3_tickets).
  #
  # rename_table renombra la tabla, la secuencia de PK (tickets_id_seq) y los cinco
  # índices con nombre por convención, pero NO renombra las secuencias por cuenta
  # ticket_dpid_seq_<account_id> ni las funciones/triggers que las consumen. Eso se
  # hace de forma explícita aquí para que el consecutivo de display_id siga funcionando.
  def up
    rename_table :tickets, :helic3_tickets

    drop_trigger('tickets_before_insert_row_tr', 'helic3_tickets', generated: true)
    drop_trigger('ticket_dpid_before_insert', 'accounts', generated: true)

    rename_ticket_sequences('ticket_dpid_seq_', 'helic3_ticket_dpid_seq_')

    create_helic3_display_id_triggers
  end

  def down
    drop_trigger('helic3_tickets_before_insert_row_tr', 'helic3_tickets', generated: true)
    drop_trigger('helic3_ticket_dpid_before_insert', 'accounts', generated: true)

    rename_ticket_sequences('helic3_ticket_dpid_seq_', 'ticket_dpid_seq_')

    rename_table :helic3_tickets, :tickets

    create_legacy_display_id_triggers
  end

  private

  def rename_ticket_sequences(from_prefix, to_prefix)
    execute <<~SQL.squish
      DO $$
      DECLARE account_record RECORD;
      BEGIN
        FOR account_record IN SELECT id FROM accounts LOOP
          IF EXISTS (SELECT 1 FROM pg_sequences WHERE sequencename = '#{from_prefix}' || account_record.id) THEN
            EXECUTE format('ALTER SEQUENCE %I RENAME TO %I',
                           '#{from_prefix}' || account_record.id,
                           '#{to_prefix}' || account_record.id);
          END IF;
        END LOOP;
      END $$;
    SQL
  end

  def create_helic3_display_id_triggers
    create_trigger('helic3_tickets_before_insert_row_tr', generated: true, compatibility: 1)
      .on('helic3_tickets')
      .before(:insert)
      .for_each(:row) do
      "NEW.display_id := nextval('helic3_ticket_dpid_seq_' || NEW.account_id);"
    end

    create_trigger('helic3_ticket_dpid_before_insert', generated: true, compatibility: 1)
      .on('accounts')
      .after(:insert)
      .for_each(:row) do
      "execute format('create sequence IF NOT EXISTS helic3_ticket_dpid_seq_%s', NEW.id);"
    end
  end

  def create_legacy_display_id_triggers
    create_trigger('tickets_before_insert_row_tr', generated: true, compatibility: 1)
      .on('tickets')
      .before(:insert)
      .for_each(:row) do
      "NEW.display_id := nextval('ticket_dpid_seq_' || NEW.account_id);"
    end

    create_trigger('ticket_dpid_before_insert', generated: true, compatibility: 1)
      .on('accounts')
      .after(:insert)
      .for_each(:row) do
      "execute format('create sequence IF NOT EXISTS ticket_dpid_seq_%s', NEW.id);"
    end
  end
end
