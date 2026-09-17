class CreateTickets < ActiveRecord::Migration[7.0]
  def up
    create_tickets_table
    create_sequences_for_existing_accounts
    create_display_id_triggers
  end

  def down
    drop_trigger('tickets_before_insert_row_tr', 'tickets', generated: true)
    drop_trigger('ticket_dpid_before_insert', 'accounts', generated: true)
    drop_table :tickets
    drop_ticket_sequences
  end

  private

  def create_tickets_table
    create_table :tickets do |t|
      t.bigint :account_id, null: false
      t.integer :display_id, null: false
      t.string :title, null: false
      t.text :description
      t.integer :status, default: 0, null: false
      t.bigint :assignee_id
      t.bigint :creator_id
      t.bigint :conversation_id
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :tickets, [:account_id, :display_id], unique: true
    add_index :tickets, :account_id
    add_index :tickets, [:assignee_id, :account_id]
    add_index :tickets, [:account_id, :status]
    add_index :tickets, :conversation_id
  end

  def create_sequences_for_existing_accounts
    execute <<~SQL.squish
      DO $$
      DECLARE account_record RECORD;
      BEGIN
        FOR account_record IN SELECT id FROM accounts LOOP
          EXECUTE format('CREATE SEQUENCE IF NOT EXISTS ticket_dpid_seq_%s', account_record.id);
        END LOOP;
      END $$;
    SQL
  end

  def create_display_id_triggers
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

  def drop_ticket_sequences
    execute <<~SQL.squish
      DO $$
      DECLARE account_record RECORD;
      BEGIN
        FOR account_record IN SELECT id FROM accounts LOOP
          EXECUTE format('DROP SEQUENCE IF EXISTS ticket_dpid_seq_%s', account_record.id);
        END LOOP;
      END $$;
    SQL
  end
end
