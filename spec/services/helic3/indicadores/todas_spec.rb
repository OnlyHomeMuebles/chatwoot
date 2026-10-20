# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Indicadores::Todas do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'PQR', codigo: 'pqr') }
  let(:tipo) { Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo') }

  def crear_garantia(abierta_at:, cerrada_at: nil)
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: abierta_at, cerrada_at: cerrada_at)
  end

  def crear_pqr(radicada_at:, respondida_at: nil)
    Helic3::Ticket.create!(account: account, title: 'Caso', categoria: categoria, tipo: tipo,
                           radicada_at: radicada_at, respondida_at: respondida_at)
  end

  def llamar(filtros: {})
    described_class.call(account: account, filtros: filtros)
  end

  it 'suma los kpis de garantias y pqr, sin mezclar sus tablas' do
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 10), cerrada_at: Time.zone.local(2026, 1, 20))
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 15))
    crear_pqr(radicada_at: Time.zone.local(2026, 1, 5), respondida_at: Time.zone.local(2026, 1, 8))
    crear_pqr(radicada_at: Time.zone.local(2026, 1, 6))

    kpis = llamar[:kpis]

    expect(kpis).to eq(total_casos: 4, garantias: 2, pqr: 2, solucionadas: 2, en_proceso: 2)
  end

  it 'mensual: une por periodo, cada fuente en su propia columna y el total sumado' do
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 10, 12, 0))
    crear_garantia(abierta_at: Time.zone.local(2026, 2, 1, 12, 0))
    crear_pqr(radicada_at: Time.zone.local(2026, 1, 12, 12, 0))

    mensual = llamar[:mensual].index_by { |fila| fila[:periodo] }

    expect(mensual['2026-01']).to eq(periodo: '2026-01', garantias: 1, pqr: 1, total: 2)
    expect(mensual['2026-02']).to eq(periodo: '2026-02', garantias: 1, pqr: 0, total: 1)
  end

  it 'filtra por anio y mes, el unico filtro compartido entre los dos expedientes' do
    crear_garantia(abierta_at: Time.zone.local(2025, 1, 1, 12, 0))
    crear_garantia(abierta_at: Time.zone.local(2026, 5, 1, 12, 0))
    crear_pqr(radicada_at: Time.zone.local(2026, 5, 1, 12, 0))

    kpis = llamar(filtros: { anio: 2026, mes: 5 })[:kpis]

    expect(kpis).to eq(total_casos: 2, garantias: 1, pqr: 1, solucionadas: 0, en_proceso: 2)
  end

  # N1 (mismo criterio de Garantias/Pqr): un filtro de ciudad/motivo/tipo no
  # aplica aqui -- solo se aceptan anio/mes, el resto se ignora sin reventar.
  it 'ignora filtros que no son anio/mes (los catalogos de garantia y pqr son distintos)' do
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 1, 12, 0))

    kpis = llamar(filtros: { anio: 2026, cobertura_ciudad_id: 999 })[:kpis]

    expect(kpis[:garantias]).to eq(1)
  end

  it 'aisla por cuenta' do
    otra_cuenta = create(:account)
    otro_ticket = create(:ticket, account: otra_cuenta)
    Helic3::Garantia.create!(account: otra_cuenta, ticket: otro_ticket, abierta_at: Time.zone.local(2026, 1, 1))
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 1))

    expect(llamar[:kpis][:garantias]).to eq(1)
  end
end
