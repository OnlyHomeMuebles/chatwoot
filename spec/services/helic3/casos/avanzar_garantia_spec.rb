# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::AvanzarGarantia do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let(:usuario) { create(:user) }

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

  # GAR-08: cerrar exige observacion; los movimientos que NO cierran no la piden.
  def avanzar(item, proceso, decision: nil, observacion: 'Se reparó en fábrica.', usuario: nil)
    usuario ||= self.usuario
    described_class.new(item: item, proceso: proceso, decision: decision,
                        observacion: observacion, usuario: usuario).call
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

  # === GAR-08: observacion obligatoria al cerrar ===

  context 'cuando el movimiento cierra el radicado (GAR-08)' do
    it 'sin observacion levanta ObservacionRequerida y NO mueve el producto' do
      item = crear_item(visita)

      expect do
        avanzar(item, entrega, observacion: '   ')
      end.to raise_error(described_class::ObservacionRequerida)

      # la transaccion revirtio el avance: el producto sigue en su proceso (CA#4)
      expect(item.reload.proceso).to eq(visita)
      expect(garantia.reload.cerrada_at).to be_nil
    end

    it 'con observacion guarda el texto, el autor y la fecha del cierre' do
      item = crear_item(visita)
      avanzar(item, entrega, observacion: 'Se reparó el espaldar; cliente firmó.')

      garantia.reload
      expect(garantia.observacion_cierre).to eq('Se reparó el espaldar; cliente firmó.')
      expect(garantia.observacion_cierre_por).to eq(usuario)
      expect(garantia.observacion_cierre_at).to be_present
    end

    it 'registra el evento garantia_finalizada con la observacion en el payload' do
      item = crear_item(visita)
      avanzar(item, entrega, observacion: 'Entregado conforme.')

      evento = garantia.ticket.eventos.find_by(tipo: 'garantia_finalizada')
      expect(evento).to be_present
      expect(evento.payload['observacion']).to eq('Entregado conforme.')
      expect(evento.actor).to eq(usuario)
    end

    it 'con varios productos, solo exige observacion al cerrar el ultimo pendiente' do
      primero = crear_item(visita)
      ultimo = crear_item(visita)

      # el primero a terminal no cierra: no exige observacion aunque venga vacia
      expect { avanzar(primero, entrega, observacion: nil) }.not_to raise_error
      expect(garantia.reload.cerrada_at).to be_nil

      # el ultimo a terminal cierra: ahora si exige observacion
      expect { avanzar(ultimo, entrega, observacion: nil) }.to raise_error(described_class::ObservacionRequerida)

      # el raise revirtio el avance en la BD, pero el objeto en memoria quedo en
      # entrega; el request real recarga objetos frescos, asi que aqui tambien.
      ultimo.reload
      avanzar(ultimo, entrega, observacion: 'Ambos resueltos.')
      expect(garantia.reload.cerrada_at).to be_present
    end
  end
end
