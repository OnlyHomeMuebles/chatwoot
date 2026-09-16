# frozen_string_literal: true

# Punto 3 (E4): clasificador determinista de intencion de PQR/garantia.
#
# NO conversa: su unico trabajo es LEER la conversacion y decidir, con salida
# JSON estricta (temperatura 0), si el cliente esta planteando una PQR o una
# garantia y, de ser asi, clasificarla contra el catalogo VIVO de la cuenta.
#
# Es la mitad "entender" del punto 3: separar entender de actuar. La accion
# (crear el expediente) la hace despues, por codigo, Helic3::Casos::RadicacionAutomatica
# usando esta clasificacion. Asi la creacion deja de depender de que el modelo
# "decida" llamar una herramienta.
class Helic3::Agents::PqrExtractor
  # lo que devuelve la clasificacion; requiere_pqr manda: si es false, el resto
  # se ignora y no se radica.
  Resultado = Struct.new(
    :requiere_pqr, :tipo_codigo, :motivo_codigo, :resumen, :descripcion, :numero_orden,
    keyword_init: true
  )

  SYSTEM = <<~PROMPT
    Eres un clasificador de intencion de postventa de Only Home (muebleria colombiana). NO
    conversas ni le respondes al cliente: solo analizas la conversacion y devuelves un JSON.

    Tu tarea: decidir si el cliente esta planteando una PETICION, QUEJA, RECLAMO, SUGERENCIA o
    una GARANTIA que amerite abrir un expediente formal, y clasificarla.

    Pon "requiere_pqr": true SOLO si el cliente reporta un caso de postventa que amerita
    expediente: un problema con un producto (danado, roto, rayado, incompleto, defectuoso), una
    devolucion o retracto, un cambio, la activacion de una garantia, o una queja/reclamo formal.
    Pon "requiere_pqr": false para saludos, preguntas informativas (precios, materiales, tiendas),
    cotizaciones, o simple seguimiento de un pedido sin reclamo.

    Si "requiere_pqr" es true, elige "tipo_codigo" y "motivo_codigo" EXACTAMENTE de las listas
    vigentes de abajo (usa el codigo, no el nombre). Si NINGUN codigo aplica con claridad, pon
    "requiere_pqr": false y no inventes.

    Devuelve UNICAMENTE un JSON con esta forma exacta:
    {
      "requiere_pqr": true|false,
      "tipo_codigo": "<codigo de la lista o null>",
      "motivo_codigo": "<codigo de la lista o null>",
      "resumen": "<titulo corto del caso o null>",
      "descripcion": "<lo que reporto el cliente, en sus terminos, o null>",
      "numero_orden": "<numero de factura u orden si el cliente lo dio, o null>"
    }
  PROMPT

  # Por defecto usa el MISMO proveedor/modelo/credenciales que la corrida del agente
  # (Helic3::Agents::LlmRuntime): asi el clasificador nunca corre en un proveedor
  # distinto al que responde al cliente. Los parametros son inyectables para pruebas.
  def initialize(account:, model: nil, api_key: nil, api_base: nil)
    @account = account
    @model = model || Helic3::Agents::LlmRuntime.model
    @api_key = api_key || Helic3::Agents::LlmRuntime.api_key
    @api_base = api_base || Helic3::Agents::LlmRuntime.api_base
  end

  # @param conversacion_texto [String] la conversacion (cliente y asistente) ya formateada
  # @return [Resultado, nil] nil ante error del LLM o JSON invalido (se trata como "sin senal")
  def call(conversacion_texto)
    return nil if conversacion_texto.blank?

    # Sin credencial NO se falla en silencio: se registra el error (era el hueco
    # que reintroducia el bug que este flujo viene a eliminar).
    if @api_key.blank?
      Rails.logger.error(
        "[Helic3] PqrExtractor sin credencial LLM (proveedor=#{Helic3::Agents::LlmRuntime.provider}); " \
        'no se pudo clasificar el caso'
      )
      return nil
    end

    crudo = pedir_clasificacion(conversacion_texto)
    return nil if crudo.blank?

    parsear(crudo)
  rescue RubyLLM::Error, JSON::ParserError => e
    Rails.logger.warn("[Helic3] PqrExtractor no clasifico account=#{@account.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def pedir_clasificacion(texto)
    Llm::Config.with_api_key(@api_key, api_base: @api_base) do |context|
      # provider :openai cubre OpenAI y los endpoints openai-compatibles (Gemini, Groq,
      # Ollama); assume_model_exists evita que RubyLLM valide el modelo contra su registro
      # (los modelos de Gemini/Groq no estan ahi), igual que hace el gem ai-agents.
      chat = context.chat(model: @model, provider: :openai, assume_model_exists: true)
      chat.with_temperature(0)
      chat.with_instructions("#{SYSTEM}\n\n#{listas_vigentes}")
      chat.with_params(response_format: { type: 'json_object' })
      chat.ask(texto).content
    end
  end

  # Las listas del catalogo se inyectan por corrida (nunca se clavan aqui): un
  # motivo nuevo aparece solo, sin tocar este archivo. Igual criterio que AGT-02.
  def listas_vigentes
    tipos = Helic3::Catalogo::Tipo.activos.where(account: @account)
                                  .pluck(:codigo, :nombre).map { |c, n| "- #{c}: #{n}" }.join("\n")
    motivos = Helic3::Catalogo::MotivoPqr.activos.where(account: @account)
                                         .pluck(:codigo, :nombre).map { |c, n| "- #{c}: #{n}" }.join("\n")
    <<~LISTAS
      # tipo_codigo vigentes
      #{tipos}

      # motivo_codigo vigentes
      #{motivos}
    LISTAS
  end

  # El JSON del modelo se valida contra el catalogo: un tipo o motivo que no
  # exista en la cuenta se descarta (requiere_pqr=false efectivo), nunca se
  # radica con un codigo inventado.
  def parsear(crudo)
    datos = JSON.parse(crudo)
    return Resultado.new(requiere_pqr: false) unless datos['requiere_pqr']

    Resultado.new(
      requiere_pqr: true,
      tipo_codigo: datos['tipo_codigo'].presence,
      motivo_codigo: datos['motivo_codigo'].presence,
      resumen: datos['resumen'].presence,
      descripcion: datos['descripcion'].presence,
      numero_orden: datos['numero_orden'].presence
    )
  end
end
