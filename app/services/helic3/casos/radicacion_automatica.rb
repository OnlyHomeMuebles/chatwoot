# frozen_string_literal: true

# AGT-06: la COMPUERTA determinista de radicacion.
#
# Es la mitad "actuar" del ticket. Toma la clasificacion del PqrExtractor y,
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

    clasificacion = clasificar
    return :sin_senal if clasificacion.nil?

    radicar_seguro(*clasificacion)
  rescue StandardError => e
    # nunca tumba el flujo de respuesta al cliente; el error queda visible (CAS-01)
    Rails.logger.error("[Helic3] radicacion automatica fallo conv=#{@conversation&.id}: #{e.class}: #{e.message}")
    :error
  end

  private

  # Corre el clasificador y valida sus codigos contra el catalogo vivo.
  # @return [Array(Resultado, Tipo, MotivoPqr), nil] los datos para radicar, o nil si no procede
  def clasificar
    resultado = @extractor.call(conversacion_texto)
    return nil if resultado.nil? || !resultado.requiere_pqr

    tipo = Helic3::Catalogo::Tipo.activos.find_by(account: @account, codigo: resultado.tipo_codigo)
    motivo = Helic3::Catalogo::MotivoPqr.activos.find_by(account: @account, codigo: resultado.motivo_codigo)
    return nil if tipo.nil? || motivo.nil?

    [resultado, tipo, motivo]
  end

  # idempotencia acotada al expediente VIGENTE (respondida_at: nil): no se duplica el
  # caso en curso, pero un caso nuevo en un hilo abierto —una PQR vive hasta 15 dias
  # habiles y el cliente puede reportar un segundo producto— SI vuelve a ser radicable
  # una vez respondida la anterior. Eso es lo que exige el modelo legal (evita que el
  # agente le confirme al cliente un caso que no existe).
  def expediente_existente?
    @account.tickets.exists?(conversation_id: @conversation.id, respondida_at: nil)
  end

  # El candado serializa dos jobs simultaneos (dos mensajes seguidos) sobre la misma
  # conversacion: la clasificacion (lenta, con LLM) ya corrio FUERA del candado; aqui solo
  # entra la verificacion + creacion, con un re-chequeo que corta la carrera (el indice de
  # conversation_id no es unico, asi que el guard es en codigo). Se bloquea la fila con un
  # SELECT FOR UPDATE sobre un registro FRESCO (no @conversation, que puede traer atributos
  # sin persistir —display_id— por como Chatwoot crea la conversacion).
  def radicar_seguro(resultado, tipo, motivo)
    Conversation.transaction do
      Conversation.lock.find(@conversation.id)
      if expediente_existente?
        :ya_existe
      else
        radicar(resultado, tipo, motivo)
      end
    end
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
