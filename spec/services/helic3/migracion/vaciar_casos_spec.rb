# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Migracion::VaciarCasos do
  let(:account) { create(:account) }
  let!(:etapa) { Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nuevo', codigo: 'nuevo', inicial: true) }
  let!(:parametro) do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'radicado_garantia_inicio', valor: '5000',
                                        unidad: 'cantidad')
  end

  # un caso completo del cuarto de PQR, con un evento que apunta a la garantía (el bug FK)
  let!(:ticket) { Helic3::Ticket.create!(account: account, title: 'Caso', etapa: etapa) }
  let!(:datos) { ticket.create_datos!(account: account, fuentes: {}, productos: []) }
  let!(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let!(:item) { garantia.items.create!(account: account, producto_nombre: 'MESA') }
  let!(:evento) do
    Helic3::Evento.create!(account: account, ticket: ticket, garantia: garantia,
                           tipo: 'garantia_abierta', origen: 'humano', payload: {})
  end
  let!(:actividad) { ticket.actividades.create!(account: account, titulo: 'Nota', detalle: 'x') }
  let!(:documento) do
    doc = Helic3::Documento.new(account: account, ticket: ticket, garantia: garantia, clase: 'formato',
                                origen: 'sistema', ocurrido_at: Time.current, metadata: {})
    doc.archivo.attach(io: StringIO.new('pdf'), filename: 'f.pdf', content_type: 'application/pdf')
    doc.save!
    doc
  end
  let!(:devolucion) { Helic3::Devolucion.create!(account: account, ticket: ticket) }
  let!(:devolucion_item) { devolucion.items.create!(account: account, producto_nombre: 'SILLA') }

  let(:corrida) { Helic3::Migracion::Corrida.create!(account: account, tipo: 'vaciado', estado: 'simulando') }

  it 'vacía todo el cuarto de PQR sin chocar con las FK (evento → garantía)' do
    described_class.call(corrida: corrida)

    expect(Helic3::Ticket.where(account: account).count).to eq(0)
    expect(Helic3::Garantia.where(account: account).count).to eq(0)
    expect(Helic3::Evento.where(account: account).count).to eq(0)
    expect(Helic3::Documento.where(account: account).count).to eq(0)
    expect(Helic3::TicketDato.where(account: account).count).to eq(0)
    expect(Helic3::Devolucion.where(account: account).count).to eq(0)
    expect(Helic3::DevolucionItem.where(account: account).count).to eq(0)
  end

  it 'conserva la configuración (catálogos y parámetros)' do
    described_class.call(corrida: corrida)

    expect(Helic3::Catalogo::EtapaPqr.where(account: account).count).to eq(1)
    expect(Helic3::Catalogo::Parametro.where(account: account).count).to eq(1)
  end

  it 'reinicia las secuencias: PQR en 1, garantía en el inicio configurado' do
    described_class.call(corrida: corrida)

    nuevo = Helic3::Ticket.create!(account: account, title: 'Nuevo caso', etapa: etapa)
    nueva = Helic3::Garantia.create!(account: account, ticket: nuevo)
    expect(nuevo.display_id).to eq(1)
    expect(nueva.display_id).to eq(5000)
  end

  it 'registra los conteos por tabla en la corrida' do
    described_class.call(corrida: corrida)

    expect(corrida.reload.estado).to eq('completada')
    expect(corrida.conteos['tickets']).to eq(1)
    expect(corrida.conteos['eventos']).to eq(1)
    expect(corrida.conteos['documentos']).to eq(1)
  end
end
