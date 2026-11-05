# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Indicadores::Devoluciones do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  let(:manizales) do
    Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales')
  end
  let(:cambio_talla) do
    Helic3::Catalogo::MotivoDevolucion.create!(account: account, nombre: 'Cambio de talla', codigo: 'cambio_talla')
  end
  let(:no_satisfecho) do
    Helic3::Catalogo::MotivoDevolucion.create!(account: account, nombre: 'Cliente no satisfecho', codigo: 'no_satisfecho')
  end
  let(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica', codigo: 'visita_tecnica',
                                              posicion: 1)
  end
  let(:entrega) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Entrega de producto',
                                              codigo: 'entrega_producto', posicion: 5, es_terminal: true)
  end

  def crear_devolucion(abierta_at:, cerrada_at: nil, ciudad: nil, productos: [])
    devolucion = Helic3::Devolucion.create!(account: account, ticket: ticket, abierta_at: abierta_at,
                                            cerrada_at: cerrada_at, cobertura_ciudad: ciudad)
    productos.each { |atributos| Helic3::DevolucionItem.create!(account: account, devolucion: devolucion, **atributos) }
    devolucion
  end

  def llamar(filtros: {})
    described_class.call(account: account, filtros: filtros)
  end

  describe 'dos casos sembrados' do
    before do
      crear_devolucion(abierta_at: Time.zone.local(2026, 1, 10), cerrada_at: Time.zone.local(2026, 1, 20),
                       ciudad: manizales,
                       productos: [{ producto_nombre: 'Silla Nogal', motivo_devolucion: cambio_talla, proceso: entrega }])
      crear_devolucion(abierta_at: Time.zone.local(2026, 1, 15),
                       productos: [
                         { producto_nombre: 'Cama King', motivo_devolucion: no_satisfecho, proceso: visita },
                         { producto_nombre: 'Nochero Sion', motivo_devolucion: cambio_talla, proceso: visita }
                       ])
    end

    it 'kpis: 2 devoluciones, 1 solucionada, 1 en proceso, 3 productos' do
      expect(llamar[:kpis]).to eq(devoluciones: 2, solucionadas: 1, en_proceso: 1, productos: 3)
    end

    it 'mensual trae solucionadas/en_proceso por radicado, no por producto' do
      mensual = llamar[:mensual].index_by { |fila| fila[:periodo] }

      expect(mensual['2026-01']).to eq(periodo: '2026-01', cantidad: 2, solucionadas: 1, en_proceso: 1)
    end

    it 'por_ciudad: Manizales 1, la devolucion sin ciudad queda excluida' do
      por_ciudad = llamar[:por_ciudad].index_by { |fila| fila[:etiqueta] }

      expect(por_ciudad['Manizales'][:cantidad]).to eq(1)
      expect(por_ciudad).not_to have_key(nil)
    end

    it 'por_motivo cuenta PRODUCTOS, no radicados: cambio_talla aparece 2 veces' do
      por_motivo = llamar[:por_motivo].index_by { |fila| fila[:etiqueta] }

      expect(por_motivo['Cambio de talla'][:cantidad]).to eq(2)
      expect(por_motivo['Cliente no satisfecho'][:cantidad]).to eq(1)
    end

    it 'por_proceso reusa el catalogo de Garantias: visita tecnica 2, entrega 1' do
      por_proceso = llamar[:por_proceso].index_by { |fila| fila[:etiqueta] }

      expect(por_proceso['Visita técnica'][:cantidad]).to eq(2)
      expect(por_proceso['Entrega de producto'][:cantidad]).to eq(1)
    end

    # Paridad con el Dash CX ("Devoluciones por motivo"): matriz motivo x
    # trimestre, y su despliegue por mes para el click en un trimestre.
    it 'motivo_por_trimestre: cambio_talla 2 en T1, no_satisfecho 1 en T1' do
      por_trimestre = llamar[:motivo_por_trimestre].index_by { |fila| fila[:motivo] }

      expect(por_trimestre['Cambio de talla']).to eq(motivo: 'Cambio de talla', t1: 2, t2: 0, t3: 0, t4: 0, total: 2)
      expect(por_trimestre['Cliente no satisfecho'][:t1]).to eq(1)
    end

    it 'motivo_por_mes trae el desglose mes a mes para desplegar un trimestre' do
      por_mes = llamar[:motivo_por_mes].select { |fila| fila[:motivo] == 'Cambio de talla' }

      expect(por_mes).to contain_exactly({ motivo: 'Cambio de talla', periodo: '2026-01', cantidad: 2 })
    end
  end

  # B1 (mismo criterio de Garantias): se agrupa en hora de Bogota, no UTC.
  it 'agrupa por hora de Bogota: abierta a las 21:00 del 31 de enero en Bogota cuenta en enero' do
    crear_devolucion(abierta_at: Time.utc(2026, 2, 1, 2, 0))

    periodos = llamar[:mensual].map { |fila| fila[:periodo] }

    expect(periodos).to eq(['2026-01'])
  end

  it 'filtra por anio y mes' do
    crear_devolucion(abierta_at: Time.zone.local(2025, 1, 1, 12, 0))
    crear_devolucion(abierta_at: Time.zone.local(2026, 5, 1, 12, 0))

    expect(llamar(filtros: { anio: 2026, mes: 5 })[:kpis][:devoluciones]).to eq(1)
  end

  it 'ignora un anio/mes no numerico en vez de tumbar la consulta' do
    crear_devolucion(abierta_at: Time.zone.local(2026, 1, 1))

    expect(llamar(filtros: { anio: 'abc', mes: 'xyz' })[:kpis][:devoluciones]).to eq(1)
  end

  it 'aisla por cuenta' do
    otra_cuenta = create(:account)
    otro_ticket = create(:ticket, account: otra_cuenta)
    Helic3::Devolucion.create!(account: otra_cuenta, ticket: otro_ticket, abierta_at: Time.zone.local(2026, 1, 1))
    crear_devolucion(abierta_at: Time.zone.local(2026, 1, 1))

    expect(llamar[:kpis][:devoluciones]).to eq(1)
  end

  describe '#casos (mismo patron de Helic3::Indicadores::Garantias#casos)' do
    before do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_total_garantia', valor: '30',
                                          unidad: 'dias_habiles')
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_verde_garantia', valor: '15',
                                          unidad: 'dias_habiles')
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_amarillo_garantia', valor: '5',
                                          unidad: 'dias_habiles')
    end

    it 'ordena vencidas antes que solucionadas, y pagina' do
      vencida = crear_devolucion(abierta_at: 60.days.ago, ciudad: manizales,
                                 productos: [{ producto_nombre: 'Camisa', proceso: visita }])
      solucionada = crear_devolucion(abierta_at: 5.days.ago, cerrada_at: Time.current,
                                     productos: [{ producto_nombre: 'Pantalón', proceso: entrega }])

      resultado = described_class.new(account: account, filtros: {}).casos(pagina: 1)

      expect(resultado[:total]).to eq(2)
      ids = resultado[:casos].map { |fila| fila[:id] }
      expect(ids).to eq([vencida.id, solucionada.id])
      expect(resultado[:casos].first[:vencimiento][:estado]).to eq('rojo')
      expect(resultado[:casos].second[:etapa]).to eq('solucionada')
    end

    it 'respeta los mismos filtros que los agregados' do
      crear_devolucion(abierta_at: Time.zone.local(2026, 1, 1), ciudad: manizales,
                       productos: [{ producto_nombre: 'Camisa', proceso: visita }])
      crear_devolucion(abierta_at: Time.zone.local(2026, 1, 1),
                       productos: [{ producto_nombre: 'Pantalón', proceso: visita }])

      resultado = described_class.new(account: account, filtros: { cobertura_ciudad_id: manizales.id })
                                 .casos(pagina: 1)

      expect(resultado[:total]).to eq(1)
      expect(resultado[:casos].first[:centro_operacion]).to eq('Manizales')
    end
  end
end
