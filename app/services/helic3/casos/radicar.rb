# CAS-01: la unica puerta por la que nace un expediente en el sistema. Todo
# consumidor (la tool del agente, el controlador de la API, un rake futuro)
# radica por aqui, y por eso todo expediente nace completo: con etapa inicial,
# sello de radicacion y fecha de vencimiento calculada en dias habiles
# colombianos. Un servicio, dos consumidores: nunca dos implementaciones.
#
# La categoria NUNCA se recibe: se deriva del motivo (motivo_pqr.categoria).
# Lo derivable no se recibe — la misma razon del estado derivado de GAR-01:
# dos fuentes de la misma verdad terminan contandola distinto.
class Helic3::Casos::Radicar
  # error de configuracion visible: nombra la clave y la cuenta, nunca
  # un valor por defecto silencioso
  class ParametroFaltante < StandardError; end

  PLAZO_RESPALDO = 'plazo_respuesta_pqr'.freeze

  # La firma es un contrato publicado en la especificacion de la entrega
  # (la llama tambien API-02 del frente B): son los 9 parametros del
  # documento y no se cambia sin avisar.
  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, titulo:, descripcion: nil, conversation_id: nil,
                 tipo: nil, motivo_pqr: nil, creator: nil,
                 numero_orden: nil, origen: :humano)
    @account = account
    @titulo = titulo
    @descripcion = descripcion
    @conversation_id = conversation_id
    @tipo = tipo
    @motivo_pqr = motivo_pqr
    @creator = creator
    @numero_orden = numero_orden
    @origen = origen
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    Helic3::Ticket.transaction do
      Helic3::Ticket.create!(atributos)
    end
  end

  private

  def atributos
    {
      account: @account,
      title: @titulo,
      description: @descripcion,
      conversation_id: @conversation_id,
      creator: @creator,
      tipo: @tipo,
      motivo_pqr: @motivo_pqr,
      categoria: categoria_derivada,
      etapa: etapa_inicial,
      radicada_at: radicada_at,
      plazo_respuesta_vence_at: vencimiento,
      pqrs_metadata: metadata
    }
  end

  # la categoria sale del motivo y de ningun otro lado
  def categoria_derivada
    @motivo_pqr&.categoria
  end

  # find_by! a proposito: si la cuenta no tiene la etapa "nueva" es que
  # no esta sembrada, y eso debe verse en el momento, no silenciarse
  def etapa_inicial
    Helic3::Catalogo::EtapaPqr.activos.find_by!(account: @account, codigo: 'nueva')
  end

  def radicada_at
    @radicada_at ||= Time.current
  end

  # Informacion (genera_radicado false) no lleva reloj: vence en nulo.
  # El expediente se crea igual, para conservar el historial.
  def vencimiento
    return nil unless genera_radicado?

    calendario = Helic3::CalendarioHabil.new
    fecha_radicacion = radicada_at.in_time_zone(Helic3::CalendarioHabil::ZONA).to_date
    calendario.sumar_dias_habiles(fecha_radicacion, plazo_dias_habiles)
  end

  def genera_radicado?
    categoria_derivada.nil? || categoria_derivada.genera_radicado?
  end

  # cascada con cortocircuito: el dato mas especifico gana (la norma
  # especial prima sobre la general — retracto: 5, no los 15 del tipo)
  def plazo_dias_habiles
    @motivo_pqr&.plazo_dias_habiles ||
      @tipo&.plazo_dias_habiles ||
      plazo_de_respaldo
  end

  def plazo_de_respaldo
    valor = Helic3::Catalogo::Parametro
            .find_by(account_id: @account.id, clave: PLAZO_RESPALDO)
            &.valor_entero
    return valor if valor

    raise ParametroFaltante,
          "falta el parametro '#{PLAZO_RESPALDO}' en la cuenta #{@account.id} " \
          'y ni el motivo ni el tipo traen plazo'
  end

  # origen y numero de orden viajan en pqrs_metadata (columna legada que
  # encuentra aqui su segundo uso): permite distinguir despues lo que
  # radico el agente de lo que radico una persona
  def metadata
    { 'origen' => @origen.to_s, 'numero_orden' => @numero_orden }.compact
  end
end
