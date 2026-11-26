# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::VigenciaGarantia do
  let(:account) { create(:account) }
  let(:categoria_garantia) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
  end

  def expediente(radicada:, factura:, categoria: categoria_garantia)
    ticket = Helic3::Ticket.create!(account: account, title: 'Garantía',
                                    categoria: categoria, radicada_at: radicada)
    Helic3::TicketDato.create!(account: account, ticket: ticket, factura_fecha: factura) if factura
    ticket.reload
  end

  describe '.para' do
    it 'fuera del amparo: compra 13/09/2024 radicada 25/11/2026 con amparo 12' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '12', unidad: 'meses')
      v = described_class.para(expediente(radicada: Time.zone.local(2026, 11, 25, 12),
                                          factura: Date.new(2024, 9, 13)))

      expect(v[:estado]).to eq(:fuera)
      expect(v[:antiguedad_meses]).to eq(26) # 2 años y 2 meses
      expect(v[:amparo_hasta]).to eq(Date.new(2025, 9, 13))
      expect(v[:amparo_meses]).to eq(12)
    end

    it 'dentro del amparo: compra 10/02/2026 radicada 25/11/2026' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '12', unidad: 'meses')
      v = described_class.para(expediente(radicada: Time.zone.local(2026, 11, 25, 12),
                                          factura: Date.new(2026, 2, 10)))

      expect(v[:estado]).to eq(:dentro)
      expect(v[:antiguedad_meses]).to eq(9)
      expect(v[:amparo_hasta]).to eq(Date.new(2027, 2, 10))
    end

    it 'el día en que vence el amparo todavía está dentro (inclusivo)' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '12', unidad: 'meses')
      v = described_class.para(expediente(radicada: Time.zone.local(2026, 2, 10, 12),
                                          factura: Date.new(2025, 2, 10)))

      expect(v[:estado]).to eq(:dentro)
    end

    it 'sin factura_fecha: estado sin_fecha_compra y sin amparo_hasta ni antigüedad' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '12', unidad: 'meses')
      v = described_class.para(expediente(radicada: Time.zone.local(2026, 11, 25, 12), factura: nil))

      expect(v[:estado]).to eq(:sin_fecha_compra)
      expect(v[:amparo_hasta]).to be_nil
      expect(v[:antiguedad_meses]).to be_nil
    end

    it 'con amparo 24 el mismo caso de 2 años y 2 meses sigue fuera' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '24', unidad: 'meses')
      v = described_class.para(expediente(radicada: Time.zone.local(2026, 11, 25, 12),
                                          factura: Date.new(2024, 9, 13)))

      expect(v[:estado]).to eq(:fuera)
    end

    it 'con amparo 24 un caso de 1 año y 6 meses pasa a dentro' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '24', unidad: 'meses')
      v = described_class.para(expediente(radicada: Time.zone.local(2026, 11, 25, 12),
                                          factura: Date.new(2025, 5, 25)))

      expect(v[:estado]).to eq(:dentro)
      expect(v[:antiguedad_meses]).to eq(18)
    end

    it 'usa la fecha de radicación, no la de hoy: un caso radicado a tiempo sigue dentro' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '12', unidad: 'meses')
      ticket = expediente(radicada: Time.zone.local(2026, 1, 15, 12), factura: Date.new(2025, 6, 1))

      travel_to(Time.zone.local(2027, 6, 1)) do # hoy ya pasó el amparo
        expect(described_class.para(ticket)[:estado]).to eq(:dentro)
      end
    end

    it 'devuelve nil cuando el expediente no es de garantía' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '12', unidad: 'meses')
      facturacion = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Facturación',
                                                        codigo: 'facturacion')
      ticket = expediente(radicada: Time.zone.local(2026, 11, 25, 12),
                          factura: Date.new(2026, 1, 1), categoria: facturacion)

      expect(described_class.para(ticket)).to be_nil
    end

    it 'aplica cuando hay una garantía abierta aunque la categoría no sea garantia' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'amparo_garantia', valor: '12', unidad: 'meses')
      facturacion = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Facturación',
                                                        codigo: 'facturacion')
      ticket = expediente(radicada: Time.zone.local(2026, 11, 25, 12),
                          factura: Date.new(2026, 1, 1), categoria: facturacion)
      allow(ticket).to receive(:garantia).and_return(Object.new) # garantía abierta

      expect(described_class.para(ticket)).not_to be_nil
    end

    it 'cuenta sin el parámetro: devuelve nil y deja el error en el log' do
      ticket = expediente(radicada: Time.zone.local(2026, 11, 25, 12), factura: Date.new(2026, 1, 1))

      expect(Rails.logger).to receive(:error).with(/amparo_garantia/)
      expect(described_class.para(ticket)).to be_nil
    end
  end
end
