# frozen_string_literal: true

# ACT-01: el seguimiento que una persona registra en el expediente (una llamada, un
# WhatsApp, una visita a tienda). Tabla propia y no helic3_eventos: los eventos son la
# bitacora del sistema (tipos cerrados, los escribe el dominio); las actividades las
# escribe una persona y pueden crecer despues (tipo de gestion, estado).
class CreateHelic3Actividades < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_actividades do |t|
      t.references :account, null: false, foreign_key: true,
                             index: { name: 'idx_h3_actividades_account' }
      t.references :ticket, null: false, foreign_key: { to_table: :helic3_tickets, on_delete: :cascade },
                            index: false
      # on_delete: :nullify -> borrar el usuario en Chatwoot no borra el registro; el
      # nombre queda en autor_nombre (misma instantanea que Evento guarda en su payload).
      t.references :autor, foreign_key: { to_table: :users, on_delete: :nullify },
                           index: { name: 'idx_h3_actividades_autor' }
      t.string :autor_nombre
      t.string :titulo, null: false
      t.text :detalle, null: false

      t.timestamps
    end
    # el expediente pinta sus actividades por fecha
    add_index :helic3_actividades, [:ticket_id, :created_at], name: 'idx_h3_actividades_ticket_fecha'
  end
end
