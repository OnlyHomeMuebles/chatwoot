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

  def avanzar(item, proceso, decision: nil, actor: nil, origen: :humano)
    described_class.new(item: item, proceso: proceso, decision: decision, actor: actor, origen: origen).call
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

  # COR-02: el aviso al cliente sale de un evento proceso_avanzado; estos specs
  # cubren que se registre (o no) correctamente, no el envio en si (eso lo
  # prueba Helic3::Correos::NotificarCambioProceso).
  describe 'evento proceso_avanzado (COR-02)' do
    it 'registra el evento con el proceso anterior, el nuevo y el item, y encola el aviso' do
      item = crear_item(visita)

      expect(Helic3::NotificarCambioProcesoJob).to receive(:perform_later)
      avanzar(item, recoleccion)

      evento = Helic3::Evento.find_by!(ticket: ticket, tipo: 'proceso_avanzado')
      expect(evento.payload).to eq('item_id' => item.id, 'proceso_id' => recoleccion.id,
                                   'proceso_anterior_id' => visita.id)
    end

    it 'guarda el actor y el origen en el evento' do
      agente = create(:user, account: account)
      item = crear_item(visita)

      avanzar(item, recoleccion, actor: agente, origen: :humano)

      evento = Helic3::Evento.find_by!(ticket: ticket, tipo: 'proceso_avanzado')
      expect(evento.actor).to eq(agente)
      expect(evento.origen).to eq('humano')
    end

    it 'un item sin proceso previo (recien creado) SI cuenta como cambio de proceso' do
      item = garantia.items.create!(account: account, producto_nombre: 'Sofá')

      expect { avanzar(item, visita) }.to change(Helic3::Evento, :count).by(1)
    end

    it 'no registra evento ni encola nada si el proceso no cambia (mover al mismo dos veces)' do
      item = crear_item(visita)
      avanzar(item, recoleccion)

      expect(Helic3::NotificarCambioProcesoJob).not_to receive(:perform_later)
      expect { avanzar(item.reload, recoleccion) }.not_to change(Helic3::Evento, :count)
    end

    it 'no encola el aviso si la transaccion se revierte' do
      item = crear_item(visita)
      allow(item).to receive(:garantia).and_return(garantia)
      allow(garantia).to receive(:cerrar!).and_raise(ActiveRecord::Rollback)

      expect(Helic3::NotificarCambioProcesoJob).not_to receive(:perform_later)
      avanzar(item, entrega)
    end
  end
end
