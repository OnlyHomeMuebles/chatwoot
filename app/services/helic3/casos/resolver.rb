# frozen_string_literal: true

# RES-01: la puerta por la que una PQR se resuelve. Registra el resultado y
# deriva las consecuencias de las MARCAS del catalogo (cierra_pqr, abre_garantia,
# aprobacion_humana), nunca de condicionales por codigo. Un servicio, dos
# consumidores: lo llama el panel (humano) y la tool del agente (AGT-03).
# Hermano de Radicar: alli nace el expediente, aqui se resuelve.
class Helic3::Casos::Resolver
  # actor: quien resuelve. Se recibe pero aun no se persiste (no hay donde
  # guardar el autor de la resolucion): lo llenara EVT-01 (bitacora de eventos).
  # garantia: datos opcionales { cobertura_ciudad:, items: [...] } que solo se
  # usan cuando el resultado abre garantia (GAR-02).
  def initialize(ticket:, resultado:, actor: nil, origen: :humano, garantia: nil)
    @ticket = ticket
    @resultado = resultado
    @actor = actor
    @origen = origen
    @garantia = garantia
  end

  def call
    Helic3::Ticket.transaction do
      # Camino 1: el agente PROPONE algo que exige visto bueno humano. No se
      # aplica nada y el reloj sigue corriendo: legalmente la PQR no se respondio.
      if @resultado.aprobacion_humana? && @origen == :agente
        guardar_propuesta
        return @ticket
      end

      # Caminos 2 y 3: se aplica de verdad. Si venia una propuesta guardada, se
      # limpia (ya se resuelve en serio).
      limpiar_propuesta
      @ticket.resultado = @resultado
      @ticket.responder! if @resultado.cierra_pqr?
      abrir_garantia if @resultado.abre_garantia?
      @ticket.save!
      @ticket
    end
  end

  private

  # la propuesta del agente vive en pqrs_metadata (una nota al margen), NO en el
  # campo oficial resultado_id: una intencion no es un hecho consumado.
  def guardar_propuesta
    @ticket.pqrs_metadata = @ticket.pqrs_metadata.merge(
      'resultado_propuesto_id' => @resultado.id,
      'propuesto_at' => Time.current.iso8601,
      'propuesto_por' => 'agente'
    )
    @ticket.save!
  end

  # al aplicar de verdad, la propuesta pendiente ya no tiene sentido: se borra.
  def limpiar_propuesta
    @ticket.pqrs_metadata = @ticket.pqrs_metadata.except(
      'resultado_propuesto_id', 'propuesto_at', 'propuesto_por'
    )
  end

  # GAR-02: cuando el resultado abre garantia, se crea el radicado. Un resultado
  # que abre garantia SIN datos (ciudad + productos) es un 422: no se puede abrir
  # un radicado vacio. La contradiccion motivo 'nunca' la valida AbrirGarantia.
  def abrir_garantia
    raise ArgumentError, 'un resultado que abre garantia requiere ciudad y productos' if @garantia.blank?

    Helic3::Casos::AbrirGarantia.new(
      ticket: @ticket,
      cobertura_ciudad: @garantia[:cobertura_ciudad],
      items: @garantia[:items] || []
    ).call
  end
end
