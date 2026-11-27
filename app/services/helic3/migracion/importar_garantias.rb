# frozen_string_literal: true

# MIG-02 (Pieza 2, escritura): el servicio que corre una migración. Une el lector
# (CSV crudo → casos limpios), el resolvedor de catálogos (nombre → código) y la
# creación controlada de cada caso (PQR cerrada + ficha + garantía + ítems +
# actividad), persistiendo un Helic3::Migracion::Caso por consecutivo. Un solo
# camino de código para simular y para guardar: `simulacion: true` revierte la
# escritura de cada caso pero deja igual su fila de reporte (con ticket_id/garantia_id
# vacíos) y mueve las secuencias, porque esas no se revierten con la transacción.
#
# Idempotente por pqrs_metadata.consecutivo_anterior. No reusa los servicios de
# flujo (Radicar/Resolver/AvanzarGarantia): fijan Time.current, exigen cobertura y
# registran Eventos. Los ítems se crean con su proceso directo (cumple "cero
# correos" sin llamar a AvanzarGarantia; migrar a AvanzarGarantia origen :migracion
# cuando la entrega 13 esté integrada).
class Helic3::Migracion::ImportarGarantias
  ZONA = Helic3::CalendarioHabil::ZONA
  OBSERVACION_CIERRE = 'Garantía migrada del CRM anterior'
  TITULO_ACTIVIDAD = 'PQR/Garantía migrada'
  AUTOR_ACTIVIDAD = 'Migración'
  PRODUCTO_SIN_REGISTRO = 'Producto no registrado en la migración'

  def initialize(corrida:, csv:, simulacion: true)
    @corrida = corrida
    @account = corrida.account
    @csv = csv
    @simulacion = simulacion
    @catalogos = Helic3::Migracion::Catalogos.new(account: @account)
    @secuencias = Helic3::Migracion::Secuencias.new(@account)
  end

  def call
    # simular y confirmar corren sobre la misma corrida: las filas de una simulación
    # previa se descartan; las reales (ok con ticket_id) se conservan para Revertir.
    @corrida.casos.where(simulacion: true).delete_all
    lectura = Helic3::Migracion::LectorDataGrid.leer(@csv)
    return fallar!("faltan columnas: #{lectura[:columnas_faltantes].join(', ')}") unless lectura[:columnas_ok]

    @casos = lectura[:casos]
    faltas = @catalogos.faltantes(@casos)
    return fallar!("faltan en catálogos: #{faltas.join(', ')}") if faltas.any?

    @totales = Hash.new(0)
    subir_secuencias_antes
    @casos.each { |caso| migrar_uno(caso) }
    @secuencias.dejar_en_max
    cerrar!
    @corrida
  end

  private

  def migrar_uno(caso)
    consecutivo = caso[:consecutivo]
    return registrar(caso, 'omitido', 'ya migrado en una corrida anterior') if ya_migrado?(consecutivo)
    return registrar(caso, 'fallido', 'número ocupado por un caso no migrado') if numero_ocupado?(consecutivo)
    # MIG-01: una garantía abierta nunca queda con el proceso vacío en silencio.
    if @catalogos.abierta?(caso) && @catalogos.proceso_para(caso).nil?
      return registrar(caso, 'fallido', "garantía abierta con proceso '#{caso[:proceso]}' fuera de la Tabla 4 de MIG-01")
    end

    ids = {}
    Helic3::Ticket.transaction(requires_new: true) do
      ticket = crear_pqr(caso, consecutivo)
      crear_ficha(ticket, caso)
      garantia = crear_garantia(ticket, caso)
      crear_actividad(ticket, caso)
      fijar_numeros(ticket, garantia, consecutivo)
      ids = { ticket_id: ticket.id, garantia_id: garantia.id }
      raise ActiveRecord::Rollback if @simulacion
    end
    # en simulación la escritura se revirtió: el reporte queda sin ids.
    registrar(caso, 'ok', nil, @simulacion ? {} : ids)
  rescue StandardError => e
    registrar(caso, 'fallido', "#{e.class}: #{e.message}")
  end

  # --- creación de un caso (idéntico en simulación y real) ---

  def crear_pqr(caso, consecutivo)
    radicada = parse_fecha_hora(caso[:fecha_creacion])
    Helic3::Ticket.create!(
      account: @account,
      title: "Garantía ##{consecutivo} – #{caso[:cliente_nombre]}",
      description: caso[:observaciones],
      assignee: @catalogos.responsable,
      tipo: @catalogos.tipo,
      motivo_pqr: @catalogos.motivo_pqr,
      categoria: @catalogos.motivo_pqr.categoria,
      resultado: @catalogos.resultado,
      etapa: @catalogos.etapa,
      pqrs_prioridad: caso[:prioridad],
      radicada_at: radicada, respondida_at: radicada, cerrada_at: radicada,
      plazo_respuesta_vence_at: vencimiento(radicada),
      pqrs_metadata: {
        'migrado' => true, 'consecutivo_anterior' => consecutivo,
        'tipo_identificacion' => caso[:tipo_identificacion],
        'ultimo_proceso_anterior' => caso[:proceso]
      }.compact
    )
  end

  def crear_ficha(ticket, caso)
    campos = {
      cedula: caso[:cedula], cliente_nombre: caso[:cliente_nombre], cliente_telefono: caso[:telefono],
      cliente_email: caso[:correo], direccion: caso[:direccion], ciudad: caso[:ciudad],
      centro_operacion_nombre: caso[:centro_operacion], factura_numero: caso[:factura_numero],
      producto_nombre: caso[:productos].first[:nombre],
      detalle_tipificado_id: @catalogos.detalle_para(caso[:productos].first[:detalle])&.id
    }.compact_blank
    campos[:factura_fecha] = parse_fecha(caso[:fecha_compra]) if caso[:fecha_compra].present?

    ticket.create_datos!(
      account: @account,
      productos: caso[:productos].map { |p| { 'nombre' => p[:nombre] } },
      fuentes: campos.keys.index_with { 'migracion' }, **campos
    )
  end

  def crear_garantia(ticket, caso)
    garantia = Helic3::Garantia.create!(
      account: @account, ticket: ticket,
      cobertura_ciudad: @catalogos.cobertura_para(caso[:ciudad]),
      abierta_at: parse_fecha_hora(caso[:fecha_creacion])
    )
    proceso = @catalogos.proceso_para(caso)
    motivo = @catalogos.motivo_para(caso)
    cerrada = !@catalogos.abierta?(caso)
    cierre = cerrada ? fin_de_dia(caso[:fecha_finalizacion]) : nil

    caso[:productos].each do |prod|
      garantia.items.create!(
        account: @account,
        producto_nombre: prod[:nombre].presence || PRODUCTO_SIN_REGISTRO,
        motivo_garantia: motivo, detalle_tipificado: @catalogos.detalle_para(prod[:detalle]),
        proceso: proceso, resuelto_at: cierre
      )
    end

    garantia.update!(cerrada_at: cierre, observacion_cierre: OBSERVACION_CIERRE, observacion_cierre_at: cierre) if cerrada
    garantia
  end

  def crear_actividad(ticket, caso)
    detalle = "Caso migrado del CRM anterior (consecutivo #{caso[:consecutivo]})."
    detalle += " Último proceso en el CRM anterior: #{caso[:proceso]}." if ultimo_proceso_relevante?(caso)
    detalle += " Ajustes: #{caso[:ajustes].join('; ')}." if caso[:ajustes].any?
    ticket.actividades.create!(account: @account, titulo: TITULO_ACTIVIDAD,
                               detalle: detalle, autor_nombre: AUTOR_ACTIVIDAD)
  end

  # en las cerradas el ítem queda en Garantía Finalizada: el proceso real del CRM
  # anterior (p. ej. CAMBIO PRODUCTO) solo se conserva en este detalle. Las negadas
  # ya lo tienen en el ítem, y PQR FINALIZADA no aporta nada.
  def ultimo_proceso_relevante?(caso)
    @catalogos.codigo_proceso(caso) == Helic3::Migracion::Catalogos::PROCESO_CERRADA &&
      caso[:proceso].strip.casecmp(Helic3::Migracion::LectorDataGrid::PROCESO_SIN_PROCESO).nonzero?
  end

  def fijar_numeros(ticket, garantia, consecutivo)
    ticket.update_columns(display_id: consecutivo)
    garantia.update_columns(display_id: consecutivo)
  end

  # --- idempotencia y colisión ---

  def ya_migrado?(consecutivo)
    Helic3::Ticket.where(account: @account)
                  .where("pqrs_metadata->>'consecutivo_anterior' = ?", consecutivo.to_s).exists?
  end

  def numero_ocupado?(consecutivo)
    Helic3::Ticket.where(account: @account, display_id: consecutivo)
                  .where("pqrs_metadata->>'migrado' IS DISTINCT FROM 'true'").exists?
  end

  # --- numeración (regla 2): subir antes, dejar en MAX al final (incl. simulación) ---

  def subir_secuencias_antes
    return if @casos.empty?

    tope = [@casos.pluck(:consecutivo).max, @secuencias.max_display_id(:helic3_tickets),
            @secuencias.max_display_id(:helic3_garantias)].compact.max
    @secuencias.subir_a(tope)
  end

  # --- reporte ---

  # Idempotente por consecutivo dentro de la corrida. Una fila real ya creada (ok con
  # su ticket_id) no se pisa: es la lista para Revertir.
  def registrar(caso, resultado, mensaje, ids = {})
    fila = @corrida.casos.find_or_initialize_by(consecutivo: caso[:consecutivo])
    unless fila.resultado == 'ok' && fila.ticket_id.present?
      fila.update!(account: @account, resultado: resultado, mensaje: mensaje,
                   ajustes: caso[:ajustes], simulacion: @simulacion, **ids)
    end
    @totales[fila.resultado] += 1
  end

  def cerrar!
    @corrida.update!(estado: @simulacion ? 'simulado' : 'completada', mensaje_error: nil,
                     total_leidos: @casos.size, total_ok: @totales['ok'],
                     total_omitidos: @totales['omitido'], total_fallidos: @totales['fallido'],
                     finalizado_at: Time.current)
  end

  def fallar!(mensaje)
    @corrida.update!(estado: 'fallida', mensaje_error: mensaje, finalizado_at: Time.current)
    @corrida
  end

  # --- fechas (America/Bogota) ---

  def zona
    ActiveSupport::TimeZone[ZONA]
  end

  # "21/10/2026, 9:48" -> Time en Bogotá
  def parse_fecha_hora(texto)
    return nil if texto.blank?

    t = DateTime.strptime(texto.strip, '%d/%m/%Y, %H:%M')
    zona.local(t.year, t.month, t.day, t.hour, t.min)
  rescue ArgumentError
    nil
  end

  # "15/8/2026" -> Date
  def parse_fecha(texto)
    return nil if texto.blank?

    Date.strptime(texto.strip, '%d/%m/%Y')
  rescue ArgumentError
    nil
  end

  # fecha de finalización a las 23:59 Bogotá, para que el cierre nunca quede antes de abrir
  def fin_de_dia(texto)
    fecha = parse_fecha(texto)
    fecha && zona.local(fecha.year, fecha.month, fecha.day, 23, 59)
  end

  def vencimiento(radicada)
    return nil if radicada.nil?

    calendario = Helic3::CalendarioHabil.new
    dia = radicada.in_time_zone(ZONA).to_date
    vence = calendario.sumar_dias_habiles(dia, plazo_dias)
    zona.local(vence.year, vence.month, vence.day).end_of_day
  end

  def plazo_dias
    @plazo_dias ||= @catalogos.motivo_pqr.plazo_dias_habiles || @catalogos.tipo.plazo_dias_habiles ||
                    Helic3::Catalogo::Parametro.find_by(account_id: @account.id,
                                                        clave: 'plazo_respuesta_pqr')&.valor_entero || 15
  end
end
