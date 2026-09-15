# frozen_string_literal: true

# Punto 3 (E4): la COMPUERTA determinista de radicacion.
#
# Es la mitad "actuar" del punto 3. Toma la clasificacion del PqrExtractor y,
# si procede, crea el expediente POR CODIGO llamando a Helic3::Casos::Radicar
# (la unica puerta de radicacion, CAS-01). Asi la creacion deja de depender de
# que el modelo "decida" llamar la herramienta: si se identifica que el cliente
# requiere PQR/garantia y hay tipo y motivo validos, se radica SI O SI.
#
# Es idempotente por conversacion: si ya existe un expediente para esa
# conversacion (por ejemplo, porque el agente ya lo radico con su herramienta),
# no crea un duplicado.
class Helic3::Casos::RadicacionAutomatica
  MAX_MENSAJES = 30

  # @param account [Account]
  # @param conversation [Conversation] la conversacion de Chatwoot (registro de BD)
  # @param extractor [Helic3::Agents::PqrExtractor, nil] inyectable para pruebas
  def initialize(account:, conversation:, extractor: nil)
    @account = account
    @conversation = conversation
    @extractor = extractor || Helic3::Agents::PqrExtractor.new(account: account)
  end

  # @return [Helic3::Ticket, Symbol] el ticket creado, o :ya_existe / :sin_senal
  def call
    return :ya_existe if expediente_existente?

    resultado = @extractor.call(conversacion_texto)
    return :sin_senal if resultado.nil? || !resultado.requiere_pqr

    tipo = Helic3::Catalogo::Tipo.activos.find_by(account: @account, codigo: resultado.tipo_codigo)
    motivo = Helic3::Catalogo::MotivoPqr.activos.find_by(account: @account, codigo: resultado.motivo_codigo)
    return :sin_senal if tipo.nil? || motivo.nil?

    radicar(resultado, tipo, motivo)
  rescue StandardError => e
    # nunca tumba el flujo de respuesta al cliente; el error queda visible (CAS-01)
    Rails.logger.error("[Helic3] radicacion automatica fallo conv=#{@conversation&.id}: #{e.class}: #{e.message}")
    :error
  end

  private

  # idempotencia: un expediente por conversacion (cubre que el agente ya haya
  # radicado con su herramienta en la misma corrida)
  def expediente_existente?
    @account.tickets.exists?(conversation_id: @conversation.id)
  end

  def radicar(resultado, tipo, motivo)
    Helic3::Casos::Radicar.new(
      account: @account,
      titulo: resultado.resumen.presence || motivo.nombre,
      descripcion: resultado.descripcion,
      conversation_id: @conversation.id,
      tipo: tipo,
      motivo_pqr: motivo,
      numero_orden: resultado.numero_orden,
      origen: :agente
    ).call
  end

  # Solo mensajes reales del hilo (entrantes del cliente y salientes del
  # asistente), sin notas privadas, etiquetados para que el clasificador
  # distinga quien dijo que. Se limita a los ultimos MAX_MENSAJES.
  def conversacion_texto
    @conversation.messages
                 .where(message_type: %i[incoming outgoing], private: false)
                 .where.not(content: [nil, ''])
                 .order(created_at: :asc)
                 .last(MAX_MENSAJES)
                 .map { |m| "#{etiqueta(m)}: #{m.content}" }
                 .join("\n")
  end

  def etiqueta(message)
    message.incoming? ? 'Cliente' : 'Asistente'
  end
end
