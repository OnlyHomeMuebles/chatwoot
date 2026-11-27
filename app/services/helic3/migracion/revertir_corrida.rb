# frozen_string_literal: true

# MIG-02 (regla 7): deshace una migración real. Borra solo los PQR que creó ESTA
# corrida (sus ticket_id), nunca otros. Si algún caso se tocó después de migrar
# (cambió el PQR, la ficha, la garantía o sus ítems, o tiene eventos, documentos,
# actividades nuevas o una devolución), no revierte nada y deja la lista en la corrida.
class Helic3::Migracion::RevertirCorrida
  def self.call(corrida:)
    new(corrida: corrida).call
  end

  def initialize(corrida:)
    @corrida = corrida
    @filas = corrida.casos.creados.where(simulacion: false).where.not(ticket_id: nil)
                    .includes(ticket: [:datos, :eventos, :documentos, :actividades, :devolucion, { garantia: :items }])
  end

  def call
    modificados = @filas.select { |fila| modificado?(fila) }.map(&:consecutivo).sort
    if modificados.any?
      return @corrida.update!(estado: 'completada',
                              mensaje_error: "No se revirtió nada: #{modificados.size} casos se modificaron " \
                                             "después de migrar (#{modificados.join(', ')})")
    end

    Helic3::Ticket.transaction do
      @filas.each { |fila| Helic3::Migracion::VaciarCasos.borrar_ticket(fila.ticket) }
    end
    Helic3::Migracion::Secuencias.new(@corrida.account).dejar_en_max
    @corrida.update!(estado: 'revertida', mensaje_error: nil, finalizado_at: Time.current)
  end

  private

  def modificado?(fila)
    ticket = fila.ticket
    registros = [ticket, ticket.datos, ticket.garantia, *ticket.garantia&.items].compact
    registros.any? { |registro| registro.updated_at > fila.updated_at } ||
      ticket.eventos.any? || ticket.documentos.any? || ticket.actividades.size > 1 || ticket.devolucion.present?
  end
end
