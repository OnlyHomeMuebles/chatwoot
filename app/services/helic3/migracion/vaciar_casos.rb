# frozen_string_literal: true

# MIG-02 (sección 5): vacía el "cuarto de PQR" de la cuenta ANTES de migrar, porque
# en producción todo es de prueba. Borra con DESTROY PQR por PQR (no delete_all),
# para que corran los dependent: :destroy y ActiveStorage purgue el archivo de los
# documentos (formatos generados, cargas manuales); delete_all dejaría blobs
# huérfanos. Conserva la configuración (catálogos, parámetros, agentes, plantillas,
# facturas, usuarios) y las conversaciones de Chatwoot con sus adjuntos.
#
# Orden por ticket: eventos y documentos primero (ambos referencian garantia_id con
# FK RESTRICT), luego ticket.destroy arrastra garantía+ítems, ficha, actividades y
# devolución. Registra la corrida de tipo vaciado con el conteo por tabla.
class Helic3::Migracion::VaciarCasos
  TABLAS = {
    'tickets' => Helic3::Ticket, 'garantias' => Helic3::Garantia,
    'garantia_items' => Helic3::GarantiaItem, 'devoluciones' => Helic3::Devolucion,
    'ticket_datos' => Helic3::TicketDato, 'eventos' => Helic3::Evento,
    'actividades' => Helic3::Actividad, 'documentos' => Helic3::Documento
  }.freeze

  def self.call(corrida:)
    new(corrida: corrida).call
  end

  # cuántos registros borraría el vaciado de la cuenta, por tabla (más los archivos de
  # los documentos), para mostrarlos ANTES de borrar.
  def self.conteos(account)
    conteos = TABLAS.transform_values { |clase| clase.where(account: account).count }
    documentos = Helic3::Documento.where(account: account).select(:id)
    conteos.merge('archivos' => ActiveStorage::Attachment.where(record_type: Helic3::Documento.name, record_id: documentos).count)
  end

  # Borrado explícito hijos -> padres: los dependent: :destroy del ticket no garantizan
  # el orden frente a las FK RESTRICT (en dev una devolución quedaba referenciando el
  # ticket). Eventos y documentos primero (apuntan a garantia_id). Lo usa también
  # RevertirCorrida.
  def self.borrar_ticket(ticket)
    ticket.eventos.destroy_all
    ticket.documentos.destroy_all  # purga el blob de ActiveStorage
    ticket.garantia&.destroy       # + ítems
    ticket.devolucion&.destroy     # + ítems
    ticket.datos&.destroy
    ticket.actividades.destroy_all
    ticket.destroy
  end

  def initialize(corrida:)
    @corrida = corrida
    @account = corrida.account
  end

  def call
    conteos = self.class.conteos(@account)

    # .ids (no find_each): borrar mientras se itera un batch se salta filas.
    Helic3::Ticket.where(account: @account).ids.each do |id|
      ticket = Helic3::Ticket.find_by(id: id)
      self.class.borrar_ticket(ticket) if ticket
    end

    Helic3::Migracion::Secuencias.new(@account).reiniciar
    @corrida.update!(estado: 'completada', conteos: conteos,
                     total_ok: conteos['tickets'], finalizado_at: Time.current)
    @corrida
  end
end
