# frozen_string_literal: true

require 'rails_helper'

# ERP-08: escribe la ficha marcando la procedencia (erp lo que trajo Siesa, humano lo
# que el agente cambio). El adaptador simulado hace de ERP: Ana Ruiz (1032456789) vive
# en Armenia, 'Cra 14 # 10-25, Barrio Centro', tel 3001112233, ana.ruiz@correo.com.
RSpec.describe Helic3::Casos::RegistrarClienteErp do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  around { |ejemplo| with_modified_env(HELIC3_ERP_MODO: 'simulado') { ejemplo.run } }

  it 'CA3: lo que coincide con el ERP queda fuente erp; la direccion cambiada queda humano' do
    datos = { cedula: '1032456789', cliente_nombre: 'Ana Ruiz', cliente_telefono: '3001112233',
              cliente_email: 'ana.ruiz@correo.com', ciudad: 'Armenia', direccion: 'Mi correccion 123' }
    described_class.new(ticket: ticket, datos: datos).call

    ficha = ticket.reload.datos
    expect(ficha.fuentes.values_at('cliente_nombre', 'cliente_telefono', 'cliente_email', 'ciudad')).to all(eq('erp'))
    expect(ficha.fuentes['direccion']).to eq('humano')
    expect(ficha.direccion).to eq('Mi correccion 123')
  end

  it 'CA4: un nombre que no coincide con el ERP queda humano; el resto queda erp' do
    datos = { cedula: '1032456789', cliente_nombre: 'Nombre Corregido', cliente_telefono: '3001112233' }
    described_class.new(ticket: ticket, datos: datos).call

    ficha = ticket.reload.datos
    expect(ficha.fuentes['cliente_nombre']).to eq('humano')
    expect(ficha.cliente_nombre).to eq('Nombre Corregido')
    expect(ficha.fuentes['cliente_telefono']).to eq('erp')
  end

  it 'CA5: si el ERP no esta disponible, escribe todo humano (no bloquea la radicacion)' do
    allow(Helic3::Erp).to receive(:adapter).and_raise(Helic3::Erp::NoDisponible)
    datos = { cedula: '1032456789', cliente_nombre: 'Ana Ruiz', cliente_telefono: '3001112233' }
    described_class.new(ticket: ticket, datos: datos).call

    expect(ticket.reload.datos.fuentes['cliente_nombre']).to eq('humano')
  end

  it 'si el ERP no encuentra al cliente, escribe todo humano' do
    datos = { cedula: '99999999', cliente_nombre: 'Desconocido', cliente_telefono: '3001112233' }
    described_class.new(ticket: ticket, datos: datos).call

    expect(ticket.reload.datos.fuentes['cliente_nombre']).to eq('humano')
  end

  it 'guarda la cedula normalizada con fuente erp aunque el agente la escriba con puntos' do
    datos = { cedula: '1.032.456.789', cliente_nombre: 'Ana Ruiz', cliente_telefono: '3001112233' }
    described_class.new(ticket: ticket, datos: datos).call

    ficha = ticket.reload.datos
    expect(ficha.cedula).to eq('1032456789')
    expect(ficha.fuentes['cedula']).to eq('erp')
  end

  it 'ante cualquier error de la consulta (no solo NoDisponible) escribe todo humano sin reventar' do
    allow(Helic3::Erp).to receive(:adapter).and_raise(StandardError, 'boom de red')
    datos = { cedula: '1032456789', cliente_nombre: 'Ana Ruiz', cliente_telefono: '3001112233' }

    expect { described_class.new(ticket: ticket, datos: datos).call }.not_to raise_error
    expect(ticket.reload.datos.fuentes['cliente_nombre']).to eq('humano')
  end
end
