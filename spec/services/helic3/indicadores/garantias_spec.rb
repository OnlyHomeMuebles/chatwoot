# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Indicadores::Garantias do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  let(:manizales) do
    Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales',
                                              tecnico_propio: true)
  end
  let(:pereira) do
    Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Pereira', codigo: 'pereira')
  end
  let(:calidad) do
    Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Calidad - producto comprado',
                                             codigo: 'calidad_producto_comprado')
  end
  let(:fabricacion) do
    Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Reparación - primera entrega',
                                             codigo: 'reparacion_primera_entrega')
  end
  let(:tela_motosa) do
    Helic3::Catalogo::DetalleTipificado.create!(account: account, nombre: 'Tela motosa', codigo: 'tela_motosa',
                                                motivo_garantia: calidad)
  end
  let(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica', codigo: 'visita_tecnica',
                                              posicion: 1)
  end
  let(:entrega) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Entrega de producto',
                                              codigo: 'entrega_producto', posicion: 5, es_terminal: true)
  end

  def crear_garantia(abierta_at:, cerrada_at: nil, ciudad: nil, productos: [])
    garantia = Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: abierta_at,
                                        cerrada_at: cerrada_at, cobertura_ciudad: ciudad)
    productos.each do |atributos|
      Helic3::GarantiaItem.create!(account: account, garantia: garantia, **atributos)
    end
    garantia
  end

  def llamar(filtros: {})
    described_class.call(account: account, filtros: filtros)
  end

  describe 'tres casos sembrados (CA: coincide con una consulta directa)' do
    before do
      # Enero 2026, Manizales, resuelta: un producto con motivo calidad + detalle tela motosa
      crear_garantia(abierta_at: Time.zone.local(2026, 1, 10), cerrada_at: Time.zone.local(2026, 1, 20),
                     ciudad: manizales,
                     productos: [{ producto_nombre: 'Cama King Sion', motivo_garantia: calidad,
                                   detalle_tipificado: tela_motosa, proceso: entrega }])
      # Enero 2026, Pereira, en proceso: dos productos (misma garantia) con motivos distintos
      crear_garantia(abierta_at: Time.zone.local(2026, 1, 15), ciudad: pereira,
                     productos: [
                       { producto_nombre: 'Nochero Sion', motivo_garantia: fabricacion, proceso: visita },
                       { producto_nombre: 'Cómoda Sion', motivo_garantia: calidad, proceso: visita }
                     ])
      # Marzo 2026 (T1 tambien, pero otro mes), sin ciudad, en proceso
      crear_garantia(abierta_at: Time.zone.local(2026, 3, 5),
                     productos: [{ producto_nombre: 'Silla Nogal', proceso: visita }])
    end

    it 'kpis: 3 garantias, 1 solucionada, 2 en proceso, 4 productos' do
      kpis = llamar[:kpis]

      expect(kpis).to eq(garantias: 3, solucionadas: 1, en_proceso: 2, productos: 4)
    end

    it 'mensual: enero con 2 radicados, marzo con 1' do
      mensual = llamar[:mensual].index_by { |fila| fila[:periodo] }

      expect(mensual['2026-01'][:cantidad]).to eq(2)
      expect(mensual['2026-03'][:cantidad]).to eq(1)
    end

    it 'trimestral: las tres caen en T1-2026 (una sola fila)' do
      expect(llamar[:trimestral]).to contain_exactly({ periodo: '2026-T1', cantidad: 3 })
    end

    it 'por_ciudad: Manizales 1, Pereira 1, Sin ciudad 1' do
      por_ciudad = llamar[:por_ciudad].index_by { |fila| fila[:etiqueta] }

      expect(por_ciudad['Manizales'][:cantidad]).to eq(1)
      expect(por_ciudad['Pereira'][:cantidad]).to eq(1)
      expect(por_ciudad['Sin ciudad'][:cantidad]).to eq(1)
    end

    it 'por_motivo cuenta PRODUCTOS, no radicados: calidad aparece 2 veces (en dos garantias distintas)' do
      por_motivo = llamar[:por_motivo].index_by { |fila| fila[:etiqueta] }

      expect(por_motivo['Calidad - producto comprado'][:cantidad]).to eq(2)
      expect(por_motivo['Reparación - primera entrega'][:cantidad]).to eq(1)
      expect(por_motivo['Sin motivo'][:cantidad]).to eq(1)
    end

    it 'por_detalle: solo un producto tiene detalle tipificado' do
      expect(llamar[:por_detalle]).to include({ etiqueta: 'Tela motosa', cantidad: 1 })
    end

    it 'por_proceso: visita tecnica 3, entrega de producto 1' do
      por_proceso = llamar[:por_proceso].index_by { |fila| fila[:etiqueta] }

      expect(por_proceso['Visita técnica'][:cantidad]).to eq(3)
      expect(por_proceso['Entrega de producto'][:cantidad]).to eq(1)
    end

    it 'por_producto lista cada producto con su cantidad' do
      expect(llamar[:por_producto]).to include({ etiqueta: 'Cama King Sion', cantidad: 1 },
                                               { etiqueta: 'Silla Nogal', cantidad: 1 })
    end
  end

  it 'CA: una garantia con dos productos que cumplen el filtro cuenta UNA vez en las tarjetas' do
    crear_garantia(abierta_at: Time.zone.local(2026, 2, 1),
                   productos: [
                     { producto_nombre: 'Nochero Sion', motivo_garantia: calidad },
                     { producto_nombre: 'Cómoda Sion', motivo_garantia: calidad }
                   ])

    kpis = llamar(filtros: { motivo_garantia_id: calidad.id })[:kpis]

    expect(kpis[:garantias]).to eq(1)
    expect(kpis[:productos]).to eq(2)
  end

  it 'CA: no aparecen meses posteriores al actual' do
    travel_to Time.zone.local(2026, 6, 15) do
      crear_garantia(abierta_at: Time.zone.local(2026, 6, 1))
      # fecha futura "real" no deberia existir en produccion, pero si llegara (reloj mal puesto,
      # dato corregido a mano) el indicador no debe mostrarla igual.
      futuro = Helic3::Garantia.new(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 9, 1))
      futuro.save!(validate: false)

      periodos = llamar[:mensual].map { |fila| fila[:periodo] }

      expect(periodos).to include('2026-06')
      expect(periodos).not_to include('2026-09')
    end
  end

  it 'CA: con un filtro sin resultados, todos los desgloses quedan vacios (el "sin datos" lo pinta el frontend)' do
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 1), ciudad: manizales)

    resultado = llamar(filtros: { cobertura_ciudad_id: pereira.id })

    expect(resultado[:kpis]).to eq(garantias: 0, solucionadas: 0, en_proceso: 0, productos: 0)
    expect(resultado[:mensual]).to eq([])
    expect(resultado[:por_ciudad]).to eq([])
  end

  describe 'filtros directos sobre la garantia' do
    before do
      crear_garantia(abierta_at: Time.zone.local(2025, 1, 1), ciudad: manizales)
      crear_garantia(abierta_at: Time.zone.local(2026, 1, 1), ciudad: pereira)
      crear_garantia(abierta_at: Time.zone.local(2026, 5, 1), ciudad: manizales)
    end

    it 'filtra por anio' do
      expect(llamar(filtros: { anio: 2026 })[:kpis][:garantias]).to eq(2)
    end

    it 'filtra por anio y mes combinados' do
      expect(llamar(filtros: { anio: 2026, mes: 5 })[:kpis][:garantias]).to eq(1)
    end

    it 'filtra por ciudad' do
      expect(llamar(filtros: { cobertura_ciudad_id: manizales.id })[:kpis][:garantias]).to eq(2)
    end
  end

  it 'aisla por cuenta: una garantia de otra cuenta nunca aparece' do
    otra_cuenta = create(:account)
    otro_ticket = create(:ticket, account: otra_cuenta)
    Helic3::Garantia.create!(account: otra_cuenta, ticket: otro_ticket, abierta_at: Time.zone.local(2026, 1, 1))
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 1))

    expect(llamar[:kpis][:garantias]).to eq(1)
  end
end
