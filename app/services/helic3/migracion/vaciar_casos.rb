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

  def initialize(corrida:)
    @corrida = corrida
    @account = corrida.account
  end

  def call
    conteos = TABLAS.transform_values { |clase| clase.where(account: @account).count }

    # .ids (no find_each): borrar mientras se itera un batch se salta filas.
    Helic3::Ticket.where(account: @account).ids.each do |id|
      ticket = Helic3::Ticket.find_by(id: id)
      next unless ticket

      # Borrado explícito hijos -> padres: los dependent: :destroy del ticket no
      # garantizan el orden frente a las FK RESTRICT (en dev una devolución quedaba
      # referenciando el ticket). Eventos y documentos primero (apuntan a garantia_id).
      ticket.eventos.destroy_all
      ticket.documentos.destroy_all  # purga el blob de ActiveStorage
      ticket.garantia&.destroy       # + ítems
      ticket.devolucion&.destroy     # + ítems
      ticket.datos&.destroy
      ticket.actividades.destroy_all
      ticket.destroy
    end

    reiniciar_secuencias
    @corrida.update!(estado: 'completada', conteos: conteos,
                     total_ok: conteos['tickets'], finalizado_at: Time.current)
    @corrida
  end

  private

  # PQR arranca de nuevo en 1; garantías en radicado_garantia_inicio (parámetro, o 1).
  def reiniciar_secuencias
    reiniciar("helic3_ticket_dpid_seq_#{@account.id}", 1)
    reiniciar("helic3_garantia_dpid_seq_#{@account.id}", inicio_garantia)
  end

  # is_called: false -> el próximo nextval devuelve exactamente ese valor.
  def reiniciar(secuencia, valor)
    conexion.execute("CREATE SEQUENCE IF NOT EXISTS #{secuencia}")
    conexion.execute("SELECT setval('#{secuencia}', #{valor}, false)")
  end

  def inicio_garantia
    Helic3::Catalogo::Parametro.find_by(account_id: @account.id, clave: 'radicado_garantia_inicio')&.valor_entero || 1
  end

  def conexion
    ActiveRecord::Base.connection
  end
end
