# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Indicadores::Todas do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'PQR', codigo: 'pqr') }
  let(:tipo) { Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo') }

  # garantia "suelta": cuelga de un ticket generico sin radicar, nunca cuenta
  # como PQR. Solo sirve para probar el desglose de "garantias" en aislamiento;
  # para probar el conteo de casos hay que usar crear_pqr_con_garantia.
  def crear_garantia(abierta_at:, cerrada_at: nil)
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: abierta_at, cerrada_at: cerrada_at)
  end

  def crear_pqr(radicada_at:, respondida_at: nil)
    Helic3::Ticket.create!(account: account, title: 'Caso', categoria: categoria, tipo: tipo,
                           radicada_at: radicada_at, respondida_at: respondida_at)
  end

  # el caso real (revision de Jhan, PR #134): la garantia SIEMPRE cuelga de la
  # PQR que la abrio (Helic3::Casos::AbrirGarantia, llamado desde Resolver),
  # nunca de un ticket aparte.
  def crear_pqr_con_garantia(radicada_at:, respondida_at: nil, garantia_cerrada_at: nil)
    ticket_pqr = crear_pqr(radicada_at: radicada_at, respondida_at: respondida_at)
    Helic3::Garantia.create!(account: account, ticket: ticket_pqr, abierta_at: radicada_at, cerrada_at: garantia_cerrada_at)
    ticket_pqr
  end

  def llamar(filtros: {})
    described_class.call(account: account, filtros: filtros)
  end

  it 'cuenta por expediente: una garantia no duplica el caso de su propia PQR (revision de Jhan, PR #134)' do
    crear_pqr(radicada_at: Time.zone.local(2026, 1, 5, 12, 0), respondida_at: Time.zone.local(2026, 1, 8, 12, 0)) # solucionado, sin garantia
    crear_pqr(radicada_at: Time.zone.local(2026, 1, 6, 12, 0)) # en proceso, sin garantia
    crear_pqr_con_garantia(radicada_at: Time.zone.local(2026, 1, 7, 12, 0), respondida_at: Time.zone.local(2026, 1, 9, 12, 0),
                           garantia_cerrada_at: Time.zone.local(2026, 1, 20, 12, 0)) # solucionado: respondida y garantia ya cerrada
    crear_pqr_con_garantia(radicada_at: Time.zone.local(2026, 1, 8, 12, 0),
                           respondida_at: Time.zone.local(2026, 1, 10, 12, 0)) # en proceso: respondida pero garantia sigue abierta

    kpis = llamar[:kpis]

    expect(kpis).to eq(total_casos: 4, garantias: 2, pqr: 4, solucionadas: 2, en_proceso: 2)
  end

  it 'una garantia que cuelga de una PQR radicada y resuelta no duplica el total (debe ser 1)' do
    crear_pqr_con_garantia(radicada_at: Time.zone.local(2026, 1, 5, 12, 0), respondida_at: Time.zone.local(2026, 1, 8, 12, 0),
                           garantia_cerrada_at: Time.zone.local(2026, 1, 15, 12, 0))

    kpis = llamar[:kpis]

    expect(kpis[:total_casos]).to eq(1)
    expect(kpis[:solucionadas]).to eq(1)
    expect(kpis[:en_proceso]).to eq(0)
  end

  # Bug real encontrado en datos semilla (ticket demo con 20 garantias
  # colgando del mismo ticket_id): ticket_id en helic3_garantias no tiene un
  # indice UNIQUE a nivel de base de datos, asi que un left_joins multiplica
  # las filas de ese ticket y puede inflar "en_proceso" por encima del total
  # de casos (hasta dar "solucionadas" negativo). EXISTS nunca multiplica filas.
  it 'un ticket con mas de una garantia no infla "en_proceso" por encima del total' do
    ticket_duplicado = crear_pqr(radicada_at: Time.zone.local(2026, 1, 1, 12, 0))
    5.times { |i| Helic3::Garantia.create!(account: account, ticket: ticket_duplicado, abierta_at: Time.zone.local(2026, 1, 1 + i, 12, 0)) }
    crear_pqr(radicada_at: Time.zone.local(2026, 1, 2, 12, 0), respondida_at: Time.zone.local(2026, 1, 3, 12, 0))

    kpis = llamar[:kpis]

    expect(kpis[:total_casos]).to eq(2)
    expect(kpis[:en_proceso]).to eq(1)
    expect(kpis[:solucionadas]).to eq(1)
  end

  it 'mensual: el total es el de pqr -- la garantia es desglose, no se vuelve a sumar' do
    # radicada en enero; la garantia (y su resolucion) se abre recien en febrero
    ticket_enero = crear_pqr(radicada_at: Time.zone.local(2026, 1, 12, 12, 0), respondida_at: Time.zone.local(2026, 2, 3, 12, 0))
    Helic3::Garantia.create!(account: account, ticket: ticket_enero, abierta_at: Time.zone.local(2026, 2, 3, 12, 0))
    crear_pqr(radicada_at: Time.zone.local(2026, 1, 20, 12, 0))

    mensual = llamar[:mensual].index_by { |fila| fila[:periodo] }

    expect(mensual['2026-01']).to eq(periodo: '2026-01', garantias: 0, pqr: 2, total: 2)
    expect(mensual['2026-02']).to eq(periodo: '2026-02', garantias: 1, pqr: 0, total: 0)
  end

  it 'filtra por anio y mes, el unico filtro compartido entre los dos expedientes' do
    crear_pqr(radicada_at: Time.zone.local(2025, 1, 1, 12, 0))
    crear_pqr_con_garantia(radicada_at: Time.zone.local(2026, 5, 1, 12, 0), respondida_at: Time.zone.local(2026, 5, 3, 12, 0),
                           garantia_cerrada_at: Time.zone.local(2026, 5, 10, 12, 0))

    kpis = llamar(filtros: { anio: 2026, mes: 5 })[:kpis]

    expect(kpis).to eq(total_casos: 1, garantias: 1, pqr: 1, solucionadas: 1, en_proceso: 0)
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
