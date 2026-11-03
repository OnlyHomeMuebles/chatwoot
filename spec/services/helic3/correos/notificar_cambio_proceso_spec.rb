# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Correos::NotificarCambioProceso do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica', codigo: 'visita_tecnica',
                                              posicion: 0)
  end
  let(:item) { garantia.items.create!(account: account, producto_nombre: 'Sofá', proceso: visita) }
  let(:plantilla) do
    Helic3::PlantillaCorreo.create!(account: account, proceso_garantia: visita, disparador: 'proceso_garantia',
                                    asunto: 'Tu PQR #{{RADICADO_PQR}} avanza a Visita Técnica',
                                    cuerpo: 'Hola {{CLIENTE}}, avanza a **Visita Técnica**.')
  end

  def crear_evento(payload: { 'item_id' => item.id, 'proceso_id' => visita.id, 'proceso_anterior_id' => nil })
    Helic3::Evento.registrar!(ticket: ticket, tipo: 'proceso_avanzado', origen: 'humano', garantia: garantia,
                              payload: payload)
  end

  around do |example|
    # config/initializers/mailer.rb (upstream) fuerza :sendmail sin
    # SMTP_ADDRESS en CUALQUIER ambiente, pisando el :test de
    # config/environments/test.rb -- sin esto, deliver_now intentaria el
    # sendmail real de la maquina y ActionMailer::Base.deliveries nunca se
    # llenaria. Se restaura al original para no afectar otros specs.
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    # SMTP_ADDRESS presente = smtp_config_set_or_development? da true (metodo
    # real, sin stub); el spec de smtp_no_configurado lo anula por dentro.
    with_modified_env(SMTP_ADDRESS: 'smtp.example.com') { example.run }
    ActionMailer::Base.delivery_method = original
  end

  before { plantilla } # la crea por defecto en los specs que SI esperan envio

  it 'sin plantilla activa para el proceso, no envia ni registra nada' do
    plantilla.destroy!
    evento = crear_evento

    expect { described_class.call(evento: evento) }.not_to change(ActionMailer::Base.deliveries, :size)
    expect(Helic3::Evento.where(ticket: ticket).count).to eq(1) # solo el proceso_avanzado original
  end

  it 'con la plantilla inactiva, no envia ni registra nada' do
    plantilla.update!(activo: false)
    evento = crear_evento

    expect { described_class.call(evento: evento) }.not_to change(ActionMailer::Base.deliveries, :size)
    expect(Helic3::Evento.where(ticket: ticket).count).to eq(1)
  end

  it 'sin correo del cliente (ni ficha ni contacto), registra correo_no_enviado con motivo sin_correo' do
    evento = crear_evento

    described_class.call(evento: evento)

    no_enviado = Helic3::Evento.find_by!(ticket: ticket, tipo: 'correo_no_enviado')
    expect(no_enviado.payload).to include('motivo' => 'sin_correo', 'plantilla_id' => plantilla.id,
                                          'evento_origen_id' => evento.id)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'con un correo de formato invalido en la ficha, tambien registra sin_correo' do
    Helic3::TicketDato.create!(account: account, ticket: ticket, cliente_email: 'no-es-un-correo')
    evento = crear_evento

    described_class.call(evento: evento)

    expect(Helic3::Evento.find_by(ticket: ticket, tipo: 'correo_no_enviado').payload['motivo']).to eq('sin_correo')
  end

  it 'envia el correo cuando hay plantilla activa y correo valido en la ficha (MAN-01)' do
    Helic3::TicketDato.create!(account: account, ticket: ticket, cliente_nombre: 'Ana', cliente_email: 'ana@example.com')
    evento = crear_evento

    described_class.call(evento: evento)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(['ana@example.com'])
    expect(mail.subject).to include('Visita Técnica')
    expect(mail.body.to_s).to include('Ana')

    enviado = Helic3::Evento.find_by!(ticket: ticket, tipo: 'correo_enviado')
    expect(enviado.payload).to include('destinatario' => 'ana@example.com', 'plantilla_id' => plantilla.id,
                                       'evento_origen_id' => evento.id)
  end

  it 'si no esta configurado el SMTP (y no es development), registra smtp_no_configurado' do
    Helic3::TicketDato.create!(account: account, ticket: ticket, cliente_email: 'ana@example.com')
    evento = crear_evento

    with_modified_env(SMTP_ADDRESS: nil) { described_class.call(evento: evento) }

    no_enviado = Helic3::Evento.find_by!(ticket: ticket, tipo: 'correo_no_enviado')
    expect(no_enviado.payload['motivo']).to eq('smtp_no_configurado')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'si el envio falla con una excepcion SMTP, registra smtp_error (no revienta el job)' do
    Helic3::TicketDato.create!(account: account, ticket: ticket, cliente_email: 'ana@example.com')
    evento = crear_evento
    allow(Helic3::NotificacionesMailer).to receive(:with).and_raise(Net::SMTPSyntaxError, 'boom')

    expect { described_class.call(evento: evento) }.not_to raise_error

    no_enviado = Helic3::Evento.find_by!(ticket: ticket, tipo: 'correo_no_enviado')
    expect(no_enviado.payload['motivo']).to eq('smtp_error')
  end

  # cubre los reintentos de Sidekiq (ver Helic3::NotificarCambioProcesoJob).
  it 'es idempotente: si ya existe un correo_enviado para este evento, no reenvia' do
    Helic3::TicketDato.create!(account: account, ticket: ticket, cliente_email: 'ana@example.com')
    evento = crear_evento
    described_class.call(evento: evento)

    expect { described_class.call(evento: evento) }.not_to change(ActionMailer::Base.deliveries, :size)
    expect(Helic3::Evento.where(ticket: ticket, tipo: 'correo_enviado').count).to eq(1)
  end

  it 'un intento previo fallido (correo_no_enviado) SI se reintenta (no es lo que cubre la idempotencia)' do
    evento = crear_evento
    described_class.call(evento: evento) # sin ficha -> sin_correo

    Helic3::TicketDato.create!(account: account, ticket: ticket, cliente_email: 'ana@example.com')
    described_class.call(evento: evento)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it 'si el item del evento ya no existe, no hace nada' do
    evento = crear_evento(payload: { 'item_id' => -1, 'proceso_id' => visita.id, 'proceso_anterior_id' => nil })

    expect { described_class.call(evento: evento) }.not_to raise_error
    expect(Helic3::Evento.where(ticket: ticket).count).to eq(1)
  end
end
