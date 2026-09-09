# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::AbrirGarantia do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  # procesos que la ruta de la ciudad puede elegir
  let!(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica',
                                              codigo: 'visita_tecnica', posicion: 0)
  end
  let!(:recoleccion) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Recolección',
                                              codigo: 'recoleccion', posicion: 1)
  end

  let(:manizales) do
    Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales',
                                              tecnico_propio: true, origen_ruta: 'visita_tecnica')
  end
  let(:bogota) do
    Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Bogotá', codigo: 'bogota',
                                              tecnico_propio: false, origen_ruta: 'recoleccion')
  end

  def abrir(ciudad:, expediente: ticket, items: [{ producto_nombre: 'Sofá' }])
    described_class.new(ticket: expediente, cobertura_ciudad: ciudad, items: items).call
  end

  it 'crea la garantia con su display_id y su primer item' do
    garantia = abrir(ciudad: manizales)

    expect(garantia).to be_persisted
    expect(garantia.display_id).to be_present
    expect(garantia.items.count).to eq(1)
    expect(garantia.ticket).to eq(ticket)
  end

  describe 'el primer proceso sale de la ciudad, no de un if' do
    it 'ciudad con tecnico propio -> visita tecnica' do
      garantia = abrir(ciudad: manizales)
      expect(garantia.items.first.proceso).to eq(visita)
    end

    it 'ciudad sin tecnico -> recoleccion' do
      garantia = abrir(ciudad: bogota)
      expect(garantia.items.first.proceso).to eq(recoleccion)
    end

    it 'ciudad sin origen_ruta -> item sin proceso, no revienta' do
      sin_ruta = Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Leticia',
                                                           codigo: 'leticia', tecnico_propio: false)
      garantia = abrir(ciudad: sin_ruta)
      expect(garantia.items.first.proceso).to be_nil
    end
  end

  it 'es idempotente: no crea una segunda garantia para el mismo expediente' do
    primera = abrir(ciudad: manizales)
    segunda = abrir(ciudad: bogota)

    expect(segunda).to eq(primera)
    expect(ticket.reload.garantia.items.count).to eq(1)
  end

  it 'rechaza la contradiccion del catalogo: motivo con abre_garantia nunca' do
    categoria = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Comercial', codigo: 'comercial')
    motivo = Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Retracto', codigo: 'retracto',
                                                 categoria: categoria, abre_garantia: :nunca)
    ticket.update!(motivo_pqr: motivo)

    expect { abrir(ciudad: manizales) }
      .to raise_error(Helic3::Casos::AbrirGarantia::MotivoNoAbreGarantia, /retracto/)
    expect(ticket.reload.garantia).to be_nil
  end

  it 'crea un item por cada producto reportado' do
    garantia = abrir(ciudad: manizales,
                     items: [{ producto_nombre: 'Sofá' }, { producto_nombre: 'Nochero' }])
    expect(garantia.items.pluck(:producto_nombre)).to contain_exactly('Sofá', 'Nochero')
  end
end
