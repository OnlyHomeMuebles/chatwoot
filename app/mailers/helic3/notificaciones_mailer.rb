# frozen_string_literal: true

# COR-02: el correo que recibe el cliente cuando un producto cambia de proceso
# (o se cierra el caso, COR-03). Layout propio (app/views/layouts/helic3/), NO
# el de Chatwoot (mailer/base.liquid via EmailTemplate.resolver) -- el
# contenido ya viene renderizado a HTML seguro por Helic3::Correos::Renderizar,
# no hay nada que resolver con liquid.
class Helic3::NotificacionesMailer < ApplicationMailer
  layout 'layouts/helic3/notificaciones'

  # ApplicationMailer traga las excepciones SMTP (solo deja un log): aqui el
  # llamador (Helic3::Correos::NotificarCambioProceso) SI necesita enterarse
  # de la falla para registrar correo_no_enviado en la bitacora, asi que se
  # redeclara para relanzar en vez de tragarsela.
  rescue_from(*ExceptionList::SMTP_EXCEPTIONS) { |exception| raise exception }

  def correo_proceso(destinatario:, asunto:, cuerpo_html:)
    @cuerpo_html = cuerpo_html
    @firma = parametro('correo_firma')
    @sitio_web = parametro('correo_sitio_web')
    @logo_url = parametro('correo_logo_url')
    @url_facebook = parametro('correo_url_facebook')
    @url_instagram = parametro('correo_url_instagram')
    @url_tiktok = parametro('correo_url_tiktok')

    mail(to: destinatario, from: remitente, subject: asunto)
  end

  private

  def remitente
    parametro('correo_remitente') || ENV.fetch('MAILER_SENDER_EMAIL', 'Chatwoot <accounts@chatwoot.com>')
  end

  def parametro(clave)
    Helic3::Catalogo::Parametro.find_by(account: params[:account], clave: clave)&.valor
  end
end
