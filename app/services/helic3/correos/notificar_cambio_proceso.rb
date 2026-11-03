# frozen_string_literal: true

# COR-02: decide que correo sale cuando un producto de garantia cambia de
# proceso (evento proceso_avanzado), y deja constancia en la bitacora de si
# salio o por que no. Separado del job (Sidekiq) para poder probar toda esta
# logica sin colas.
class Helic3::Correos::NotificarCambioProceso
  MOTIVOS = %w[sin_correo smtp_error smtp_no_configurado].freeze

  def self.call(evento:)
    new(evento: evento).call
  end

  def initialize(evento:)
    @evento = evento
    @garantia = evento.garantia
    @ticket = evento.ticket
    @account = evento.account
  end

  def call
    return if ya_enviado?

    item = Helic3::GarantiaItem.find_by(id: @evento.payload['item_id'])
    return if item.nil? # el item pudo borrarse entre el encolado y la ejecucion del job

    plantilla = plantilla_activa
    return if plantilla.nil? # sin plantilla (o inactiva): no hay que enviar ni registrar

    destinatario = destinatario_valido
    return registrar_no_enviado('sin_correo', plantilla) if destinatario.nil?
    return registrar_no_enviado('smtp_no_configurado', plantilla) unless smtp_configurado?

    enviar(plantilla, item, destinatario)
  end

  private

  attr_reader :evento, :garantia, :ticket, :account

  # cubre los reintentos de Sidekiq: un correo_no_enviado SI puede repetirse
  # (p. ej. un reintento tras smtp_error que esta vez si sale), pero un
  # correo_enviado nunca se duplica para el mismo evento de origen.
  def ya_enviado?
    Helic3::Evento.where(ticket: ticket, tipo: 'correo_enviado')
                  .exists?(["payload->>'evento_origen_id' = ?", evento.id.to_s])
  end

  def plantilla_activa
    Helic3::PlantillaCorreo.activas.find_by(account: account, proceso_garantia_id: evento.payload['proceso_id'])
  end

  # MAN-01: primero la ficha (PQR manual sin conversacion), si no el contacto
  # de la conversacion -- mismo orden que Helic3::Formatos::DatosDelFormato.
  def destinatario_valido
    candidato = ticket.datos&.cliente_email.presence || ticket.conversation&.contact&.email.presence
    return nil if candidato.blank?

    Devise.email_regexp.match?(candidato) ? candidato : nil
  end

  def smtp_configurado?
    Helic3::NotificacionesMailer.new.smtp_config_set_or_development?
  end

  def enviar(plantilla, item, destinatario)
    datos = Helic3::Formatos::DatosDelFormato.call(item: item, user: evento.actor)
    asunto = Helic3::Correos::Renderizar.asunto(plantilla.asunto, datos)
    cuerpo_html = Helic3::Correos::Renderizar.cuerpo_html(plantilla.cuerpo, datos)

    Helic3::NotificacionesMailer.with(account: account)
                                .correo_proceso(destinatario: destinatario, asunto: asunto, cuerpo_html: cuerpo_html)
                                .deliver_now
    registrar_enviado(plantilla, destinatario)
  rescue *ExceptionList::SMTP_EXCEPTIONS => e
    Rails.logger.error("[Helic3][correo] evento=#{evento.id}: #{e.class}: #{e.message}")
    registrar_no_enviado('smtp_error', plantilla)
  end

  def registrar_no_enviado(motivo, plantilla)
    Helic3::Evento.registrar!(ticket: ticket, tipo: 'correo_no_enviado', origen: evento.origen, garantia: garantia,
                              payload: { motivo: motivo, plantilla_id: plantilla&.id, evento_origen_id: evento.id })
  end

  def registrar_enviado(plantilla, destinatario)
    Helic3::Evento.registrar!(ticket: ticket, tipo: 'correo_enviado', origen: evento.origen, garantia: garantia,
                              payload: { plantilla_id: plantilla.id, destinatario: destinatario,
                                         evento_origen_id: evento.id })
  end
end
