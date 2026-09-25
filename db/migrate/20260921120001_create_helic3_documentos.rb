# EVI-01: el archivo documental del expediente. Nace con dos procedencias
# desde el primer dia -- un documento que ES un adjunto de la conversacion
# (se referencia via attachment_id, nunca se copia el archivo) y un documento
# que nace dentro del modulo (formato generado o carga manual, con su propio
# archivo adjunto). La Semana 3 promete que los formatos de garantia "quedan
# guardados en el expediente"; una tabla que solo supiera de adjuntos de
# conversacion habria que rehacerla entonces.
#
# Tabla lateral propia del modulo; ninguna columna nueva sobre tablas upstream.
#
# on_delete: :nullify en attachment_id/message_id (revision de Jhan, B2):
# Conversations::MessagesController#destroy de Chatwoot hace
# message.attachments.destroy_all dentro de una transaccion. Sin esto, borrar
# un mensaje cuya foto ya esta vinculada a un expediente revienta la FK con
# un 500. El documento conserva titulo/remitente_nombre/ocurrido_at como
# instantanea aunque el adjunto o el mensaje de origen desaparezcan -- la
# evidencia no se pierde, solo deja de poder abrirse desde el chat (ver
# Helic3::Documento#archivo_eliminado?). Pendiente de validar con Luisa la
# preservacion de evidencia.
class CreateHelic3Documentos < ActiveRecord::Migration[7.2]
  def change
    crear_tabla
    crear_indice_unico_de_idempotencia
  end

  private

  def crear_tabla
    create_table :helic3_documentos do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'idx_h3_documentos_account' }
      t.references :ticket, null: false, foreign_key: { to_table: :helic3_tickets },
                            index: { name: 'idx_h3_documentos_ticket' }
      t.references :garantia, foreign_key: { to_table: :helic3_garantias },
                              index: { name: 'idx_h3_documentos_garantia' }

      # attachments y messages usan id: :serial (integer), no bigint: t.references
      # crearia una columna bigint apuntando a una PK integer si no se declara el
      # tipo explicito. on_delete: :nullify explicado arriba (B2).
      t.references :attachment, type: :integer, foreign_key: { on_delete: :nullify }, index: { name: 'idx_h3_documentos_attachment' }
      t.references :message, type: :integer, foreign_key: { on_delete: :nullify }, index: { name: 'idx_h3_documentos_message' }
      # on_delete: :nullify -> borrar un User en Chatwoot no debe reventar; el nombre
      # ya queda como instantanea en remitente_nombre (mas abajo).
      t.references :remitente_user, foreign_key: { to_table: :users, on_delete: :nullify },
                                    index: { name: 'idx_h3_documentos_remitente_user' }

      t.string :clase, null: false # evidencia | formato
      t.string :origen, null: false # cliente | operador | agente | sistema
      t.string :remitente_nombre # instantanea del nombre de quien lo envio
      t.datetime :ocurrido_at, null: false # cuando se envio o se genero; no es created_at
      t.string :titulo
      t.text :descripcion
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end

  # Idempotencia (EVI-01): un mismo adjunto no puede vincularse dos veces al
  # mismo expediente. La base de datos la garantiza, no el codigo -- es lo
  # que permite que VincularEvidencias corra cien veces sin duplicar nada.
  # Parcial porque attachment_id es nulable (procedencia B no lo trae).
  def crear_indice_unico_de_idempotencia
    add_index :helic3_documentos, [:ticket_id, :attachment_id], unique: true,
                                                                where: 'attachment_id IS NOT NULL',
                                                                name: 'idx_h3_documentos_ticket_attachment_unico'
  end
end
