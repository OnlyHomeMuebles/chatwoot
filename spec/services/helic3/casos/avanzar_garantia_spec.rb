# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::AvanzarGarantia do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }

  let(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica',
                                              codigo: 'visita_tecnica', posicion: 0)
  end
  let(:recoleccion) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Recolección',
                                              codigo: 'recoleccion', posicion: 1)
  end
  let(:entrega) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Entrega de producto',
                                              codigo: 'entrega_producto', posicion: 2, es_terminal: true)
  end
  let(:negada) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Garantía negada',
                                              codigo: 'garantia_negada', posicion: 3, es_terminal: true)
  end

  def crear_item(proceso)
    garantia.items.create!(account: account, producto_nombre: 'Sofá', proceso: proceso)
  end

  def avanzar(item, proceso, decision: nil)
    described_class.new(item: item, proceso: proceso, decision: decision).call
  end

  it 'avanzar a un proceso terminal sella resuelto_at' do
    item = crear_item(visita)
    avanzar(item, entrega)

    expect(item.reload.resuelto_at).to be_present
  end

  it 'devolver a un proceso no terminal limpia resuelto_at' do
    item = crear_item(entrega)
    avanzar(item, visita)

    expect(item.reload.resuelto_at).to be_nil
  end

  it 'con dos productos, uno terminal y otro no, la garantia NO cierra' do
    pendiente = crear_item(visita)
    crear_item(visita)
    avanzar(pendiente, entrega)

    expect(garantia.reload.cerrada_at).to be_nil
  end

  it 'con todos los productos en proceso terminal, la garantia cierra' do
    item = crear_item(visita)
    avanzar(item, entrega)

    expect(garantia.reload.cerrada_at).to be_present
  end

  it 'garantia negada tambien cierra (terminal por dato del catalogo) y guarda la decision' do
    item = crear_item(visita)
    avanzar(item, negada, decision: 'sin cobertura')

    expect(garantia.reload.cerrada_at).to be_present
    expect(item.reload.decision).to eq('sin cobertura')
  end

  it 'avanzar de visita a recoleccion no mueve abierta_at ni resuelve el producto' do
    item = crear_item(visita)
    abierta = garantia.reload.abierta_at
    avanzar(item, recoleccion)

    expect(garantia.reload.abierta_at).to eq(abierta)
    expect(item.reload.resuelto_at).to be_nil
  end
end
