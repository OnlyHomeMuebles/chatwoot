# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Indicadores::Pqr do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account) }

  let(:categoria_pqr) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'PQR', codigo: 'pqr', genera_radicado: true)
  end
  let(:categoria_info) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Información', codigo: 'informacion',
                                        genera_radicado: false)
  end
  let(:tipo_reclamo) { Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo') }
  let(:motivo_calidad) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Calidad', codigo: 'calidad', categoria: categoria_pqr)
  end
  let(:motivo_entrega) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Entrega', codigo: 'entrega', categoria: categoria_pqr)
  end
  let(:resultado_aprobado) do
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Aprobado', codigo: 'aprobado')
  end

  # rubocop:disable Metrics/ParameterLists -- kwargs opcionales para armar un ticket de prueba sin Radicar
  def crear_ticket(radicada_at:, respondida_at: nil, plazo_respuesta_vence_at: nil, categoria: categoria_pqr,
                   tipo: tipo_reclamo, motivo_pqr: motivo_calidad, resultado: nil, assignee: nil)
    # rubocop:enable Metrics/ParameterLists
    Helic3::Ticket.create!(account: account, title: 'Caso de prueba', categoria: categoria, tipo: tipo,
                           motivo_pqr: motivo_pqr, resultado: resultado, assignee: assignee,
                           radicada_at: radicada_at, respondida_at: respondida_at,
                           plazo_respuesta_vence_at: plazo_respuesta_vence_at)
  end

  def llamar(filtros: {})
    described_class.call(account: account, filtros: filtros)
  end

  describe 'tres casos sembrados' do
    before do
      # Enero 2026: respondida DENTRO del plazo
      crear_ticket(radicada_at: Time.zone.local(2026, 1, 10, 12, 0),
                   respondida_at: Time.zone.local(2026, 1, 15, 12, 0),
                   plazo_respuesta_vence_at: Time.zone.local(2026, 1, 31, 12, 0),
                   motivo_pqr: motivo_calidad, resultado: resultado_aprobado, assignee: agente)
      # Enero 2026: respondida FUERA del plazo
      crear_ticket(radicada_at: Time.zone.local(2026, 1, 12, 12, 0),
                   respondida_at: Time.zone.local(2026, 2, 5, 12, 0),
                   plazo_respuesta_vence_at: Time.zone.local(2026, 1, 28, 12, 0),
                   motivo_pqr: motivo_entrega)
      # Marzo 2026: sin responder, plazo ya vencido
      crear_ticket(radicada_at: Time.zone.local(2026, 3, 1, 12, 0),
                   plazo_respuesta_vence_at: Time.zone.local(2026, 3, 10, 12, 0),
                   motivo_pqr: motivo_calidad)
    end

    it 'kpis: 3 radicadas, 2 respondidas, 1 pendiente, 1 dentro de plazo, 1 vencida sin responder' do
      travel_to Time.zone.local(2026, 4, 1, 12, 0) do
        kpis = llamar[:kpis]

        expect(kpis[:radicadas]).to eq(3)
        expect(kpis[:respondidas]).to eq(2)
        expect(kpis[:pendientes]).to eq(1)
        expect(kpis[:pct_respondidas]).to eq(66.7)
        expect(kpis[:dentro_plazo]).to eq(1)
        expect(kpis[:vencidas_sin_responder]).to eq(1)
        expect(kpis[:pct_cumplimiento]).to eq(50.0)
      end
    end

    it 'CA: respondidas + pendientes = radicadas' do
      kpis = llamar[:kpis]

      expect(kpis[:respondidas] + kpis[:pendientes]).to eq(kpis[:radicadas])
    end

    it 'mensual: enero con 2 (ambas respondidas, una fuera de plazo), marzo con 1 pendiente' do
      mensual = llamar[:mensual].index_by { |fila| fila[:periodo] }

      expect(mensual['2026-01']).to eq(periodo: '2026-01', cantidad: 2, respondidas: 2, pendientes: 0)
      expect(mensual['2026-03']).to eq(periodo: '2026-03', cantidad: 1, respondidas: 0, pendientes: 1)
    end

    it 'trimestral: las tres caen en T1-2026' do
      expect(llamar[:trimestral]).to contain_exactly(
        { periodo: '2026-T1', cantidad: 3, respondidas: 2, pendientes: 1 }
      )
    end

    it 'motivo_por_trimestre: una fila por motivo, con el total correcto' do
      filas = llamar[:motivo_por_trimestre].index_by { |fila| fila[:motivo] }

      expect(filas['Calidad']).to eq(motivo: 'Calidad', t1: 2, t2: 0, t3: 0, t4: 0, total: 2)
      expect(filas['Entrega']).to eq(motivo: 'Entrega', t1: 1, t2: 0, t3: 0, t4: 0, total: 1)
    end

    it 'por_tipo: las tres PQR son Reclamo' do
      expect(llamar[:por_tipo]).to contain_exactly({ etiqueta: 'Reclamo', cantidad: 3 })
    end

    it 'por_categoria: las tres pertenecen a la categoria PQR' do
      expect(llamar[:por_categoria]).to contain_exactly({ etiqueta: 'PQR', cantidad: 3 })
    end

    # N3 (mismo patron de Garantias): sin resultado, etiqueta nil -- el frontend traduce.
    it 'por_resultado: una aprobada, dos sin resultado (nil)' do
      por_resultado = llamar[:por_resultado].index_by { |fila| fila[:etiqueta] }

      expect(por_resultado['Aprobado'][:cantidad]).to eq(1)
      expect(por_resultado[nil][:cantidad]).to eq(2)
    end

    it 'por_responsable: una asignada, dos sin asignar (nil)' do
      por_responsable = llamar[:por_responsable].index_by { |fila| fila[:etiqueta] }

      expect(por_responsable[agente.name][:cantidad]).to eq(1)
      expect(por_responsable[nil][:cantidad]).to eq(2)
    end
  end

  it 'CA: una consulta de categoria Informacion (sin radicado) no aparece en ningun conteo' do
    crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0), categoria: categoria_info)

    expect(llamar[:kpis][:radicadas]).to eq(0)
  end

  # Caso real encontrado en datos sembrados: un ticket creado a mano, sin pasar
  # por Radicar, sin categoria/tipo/motivo y sin radicada_at. DATE_TRUNC sobre
  # un radicada_at nulo agrupa con una clave nil, que reventaba agrupar_por_fecha
  # (nil.to_date) y tumbaba el endpoint completo.
  it 'un ticket sin radicada_at (nunca paso por Radicar) no revienta el calculo ni se cuenta' do
    Helic3::Ticket.create!(account: account, title: 'Registro manual sin radicar')
    crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0))

    resultado = llamar

    expect(resultado[:kpis][:radicadas]).to eq(1)
    expect(resultado[:mensual]).to contain_exactly(
      { periodo: '2026-01', cantidad: 1, respondidas: 0, pendientes: 1 }
    )
  end

  it 'CA: una PQR respondida un dia despues del vencimiento cuenta como respondida, pero no como dentro de plazo' do
    crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0),
                 respondida_at: Time.zone.local(2026, 1, 21, 12, 0),
                 plazo_respuesta_vence_at: Time.zone.local(2026, 1, 20, 12, 0))

    kpis = llamar[:kpis]

    expect(kpis[:respondidas]).to eq(1)
    expect(kpis[:dentro_plazo]).to eq(0)
  end

  # Caso real encontrado en datos sembrados: tipo/categoria son opcionales en
  # el modelo (belongs_to optional: true) -- un ticket sin tipo asignado no
  # debe mostrar una etiqueta en blanco, el frontend traduce el nil.
  it 'por_tipo: un ticket sin tipo asignado queda con etiqueta nil, no se pierde' do
    crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0), tipo: tipo_reclamo)
    crear_ticket(radicada_at: Time.zone.local(2026, 1, 2, 12, 0), tipo: nil)

    por_tipo = llamar[:por_tipo].index_by { |fila| fila[:etiqueta] }

    expect(por_tipo['Reclamo'][:cantidad]).to eq(1)
    expect(por_tipo[nil][:cantidad]).to eq(1)
  end

  it 'CA: una PQR sin responder con el plazo vencido aparece en vencidas' do
    travel_to Time.zone.local(2026, 2, 1, 12, 0) do
      crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0),
                   plazo_respuesta_vence_at: Time.zone.local(2026, 1, 20, 12, 0))

      expect(llamar[:kpis][:vencidas_sin_responder]).to eq(1)
    end
  end

  it 'sin respondidas, pct_cumplimiento es nil (no 0%, que se leeria como incumplimiento)' do
    crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0),
                 plazo_respuesta_vence_at: Time.zone.local(2026, 1, 20, 12, 0))

    expect(llamar[:kpis][:pct_cumplimiento]).to be_nil
  end

  it 'CA: no aparecen meses posteriores al actual' do
    travel_to Time.zone.local(2026, 6, 15, 12, 0) do
      crear_ticket(radicada_at: Time.zone.local(2026, 6, 1, 12, 0),
                   plazo_respuesta_vence_at: Time.zone.local(2026, 6, 20, 12, 0))
      futuro = Helic3::Ticket.new(account: account, title: 'Futuro', categoria: categoria_pqr, tipo: tipo_reclamo,
                                  motivo_pqr: motivo_calidad, radicada_at: Time.zone.local(2026, 9, 1, 12, 0))
      futuro.save!(validate: false)

      periodos = llamar[:mensual].map { |fila| fila[:periodo] }

      expect(periodos).to include('2026-06')
      expect(periodos).not_to include('2026-09')
    end
  end

  describe 'filtros directos' do
    before do
      crear_ticket(radicada_at: Time.zone.local(2025, 1, 1, 12, 0), motivo_pqr: motivo_calidad)
      crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0), motivo_pqr: motivo_calidad)
      crear_ticket(radicada_at: Time.zone.local(2026, 5, 1, 12, 0), motivo_pqr: motivo_entrega)
    end

    it 'filtra por anio' do
      expect(llamar(filtros: { anio: 2026 })[:kpis][:radicadas]).to eq(2)
    end

    it 'filtra por motivo' do
      expect(llamar(filtros: { motivo_pqr_id: motivo_entrega.id })[:kpis][:radicadas]).to eq(1)
    end

    it 'ignora un anio/mes no numerico en vez de tumbar la consulta' do
      expect(llamar(filtros: { anio: 'abc', mes: 'xyz' })[:kpis][:radicadas]).to eq(3)
    end
  end

  it 'aisla por cuenta: una PQR de otra cuenta nunca aparece' do
    otra_cuenta = create(:account)
    otra_categoria = Helic3::Catalogo::Categoria.create!(account: otra_cuenta, nombre: 'PQR', codigo: 'pqr')
    otro_tipo = Helic3::Catalogo::Tipo.create!(account: otra_cuenta, nombre: 'Reclamo', codigo: 'reclamo')
    Helic3::Ticket.create!(account: otra_cuenta, title: 'Otra cuenta', categoria: otra_categoria, tipo: otro_tipo,
                           radicada_at: Time.zone.local(2026, 1, 1, 12, 0))
    crear_ticket(radicada_at: Time.zone.local(2026, 1, 1, 12, 0))

    expect(llamar[:kpis][:radicadas]).to eq(1)
  end
end
