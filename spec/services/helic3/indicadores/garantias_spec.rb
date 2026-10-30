# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Indicadores::Garantias do
  let(:account) { create(:account) }
  let(:carga_facturas) do
    Helic3::Carga.create!(account: account, tipo: 'facturas', modo: 'anexar', nombre_archivo: 'facturas.csv')
  end
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

  def crear_factura(centro_operacion:, fecha:, numero_documento: SecureRandom.hex(4))
    Helic3::FacturaVenta.create!(account: account, carga: carga_facturas, numero_documento: numero_documento,
                                 centro_operacion: centro_operacion, fecha: fecha, valor_subtotal: 100_000)
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
      # IND-03: facturas de enero 2026 para Manizales (2) y Pereira (1), para
      # calcular el ratio garantias/facturas.
      crear_factura(centro_operacion: 'Manizales', fecha: Date.new(2026, 1, 12))
      crear_factura(centro_operacion: 'Manizales', fecha: Date.new(2026, 1, 18))
      crear_factura(centro_operacion: 'Pereira', fecha: Date.new(2026, 1, 20))
    end

    it 'kpis: 3 garantias, 1 solucionada, 2 en proceso, 4 productos, 3 facturas, ratio 100%' do
      kpis = llamar[:kpis]

      expect(kpis).to eq(garantias: 3, solucionadas: 1, en_proceso: 2, productos: 4, facturas: 3, ratio: 100.0)
    end

    it 'mensual: enero con 2 radicados (1 solucionada, 1 en proceso), marzo con 1 en proceso' do
      mensual = llamar[:mensual].index_by { |fila| fila[:periodo] }

      expect(mensual['2026-01']).to eq(periodo: '2026-01', cantidad: 2, solucionadas: 1, en_proceso: 1)
      expect(mensual['2026-03']).to eq(periodo: '2026-03', cantidad: 1, solucionadas: 0, en_proceso: 1)
    end

    it 'trimestral: las tres caen en T1-2026 (una sola fila, con su desglose solucionadas/en_proceso)' do
      expect(llamar[:trimestral]).to contain_exactly(
        { periodo: '2026-T1', cantidad: 3, solucionadas: 1, en_proceso: 2 }
      )
    end

    it 'por_ciudad: Manizales y Pereira con facturas y ratio, la garantia sin ciudad queda excluida' do
      por_ciudad = llamar[:por_ciudad].index_by { |fila| fila[:etiqueta] }

      expect(por_ciudad['Manizales']).to include(cantidad: 1, facturas: 2, ratio: 50.0)
      expect(por_ciudad['Pereira']).to include(cantidad: 1, facturas: 1, ratio: 100.0)
      expect(por_ciudad).not_to have_key(nil)
    end

    it 'por_ciudad excluye una ciudad del catalogo sin ninguna factura' do
      Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Bogotá', codigo: 'bogota')

      por_ciudad = llamar[:por_ciudad].index_by { |fila| fila[:etiqueta] }

      expect(por_ciudad).not_to have_key('Bogotá')
    end

    it 'por_motivo cuenta PRODUCTOS, no radicados: calidad aparece 2 veces (en dos garantias distintas)' do
      por_motivo = llamar[:por_motivo].index_by { |fila| fila[:etiqueta] }

      expect(por_motivo['Calidad - producto comprado'][:cantidad]).to eq(2)
      expect(por_motivo['Reparación - primera entrega'][:cantidad]).to eq(1)
      expect(por_motivo[nil][:cantidad]).to eq(1)
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
      # mediodia UTC para no cruzar el borde del mes al convertir a Bogota (UTC-5)
      crear_garantia(abierta_at: Time.zone.local(2026, 6, 1, 12, 0))
      # fecha futura "real" no deberia existir en produccion, pero si llegara (reloj mal puesto,
      # dato corregido a mano) el indicador no debe mostrarla igual.
      futuro = Helic3::Garantia.new(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 9, 1, 12, 0))
      futuro.save!(validate: false)

      periodos = llamar[:mensual].map { |fila| fila[:periodo] }

      expect(periodos).to include('2026-06')
      expect(periodos).not_to include('2026-09')
    end
  end

  # B1 (revision de Jhan, PR #113): abierta_at se agrupa en hora de Bogota, no en UTC.
  it 'CA (revision de Jhan, B1): una garantia abierta el ultimo dia del mes a las 21:00 de Bogota cuenta en ese mes' do
    # 2026-01-31 21:00 hora Bogota == 2026-02-01 02:00 UTC. Sin la conversion de
    # zona, DATE_TRUNC la agruparia (mal) en febrero.
    crear_garantia(abierta_at: Time.utc(2026, 2, 1, 2, 0))

    periodos = llamar[:mensual].map { |fila| fila[:periodo] }

    expect(periodos).to eq(['2026-01'])
  end

  it 'CA: con un filtro sin resultados, todos los desgloses quedan vacios (el "sin datos" lo pinta el frontend)' do
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 1), ciudad: manizales)

    resultado = llamar(filtros: { cobertura_ciudad_id: pereira.id })

    expect(resultado[:kpis]).to eq(garantias: 0, solucionadas: 0, en_proceso: 0, productos: 0, facturas: 0, ratio: 0.0)
    expect(resultado[:mensual]).to eq([])
    expect(resultado[:por_ciudad]).to eq([])
  end

  describe 'filtros directos sobre la garantia' do
    before do
      # mediodia UTC para no cruzar el borde del mes/anio al convertir a Bogota (UTC-5)
      crear_garantia(abierta_at: Time.zone.local(2025, 1, 1, 12, 0), ciudad: manizales)
      crear_garantia(abierta_at: Time.zone.local(2026, 1, 1, 12, 0), ciudad: pereira)
      crear_garantia(abierta_at: Time.zone.local(2026, 5, 1, 12, 0), ciudad: manizales)
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

    # N1 (revision de Jhan, PR #113): un anio/mes no numerico tumbaba la consulta con un 500
    # (Postgres comparando numeric con texto) -- ahora se ignora como si no se hubiera filtrado.
    it 'ignora un anio/mes no numerico en vez de tumbar la consulta' do
      expect(llamar(filtros: { anio: 'abc', mes: 'xyz' })[:kpis][:garantias]).to eq(3)
    end
  end

  it 'aisla por cuenta: una garantia de otra cuenta nunca aparece' do
    otra_cuenta = create(:account)
    otro_ticket = create(:ticket, account: otra_cuenta)
    Helic3::Garantia.create!(account: otra_cuenta, ticket: otro_ticket, abierta_at: Time.zone.local(2026, 1, 1))
    crear_garantia(abierta_at: Time.zone.local(2026, 1, 1))

    expect(llamar[:kpis][:garantias]).to eq(1)
  end

  describe '#casos (mockup v12: detalle de clientes y casos)' do
    before do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_total_garantia', valor: '30',
                                          unidad: 'dias_habiles')
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_verde_garantia', valor: '15',
                                          unidad: 'dias_habiles')
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_amarillo_garantia', valor: '5',
                                          unidad: 'dias_habiles')
    end

    it 'ordena vencidas antes que solucionadas, y pagina' do
      vencida = crear_garantia(abierta_at: 60.days.ago, ciudad: manizales,
                               productos: [{ producto_nombre: 'Cama', proceso: visita }])
      solucionada = crear_garantia(abierta_at: 5.days.ago, cerrada_at: Time.current, ciudad: pereira,
                                   productos: [{ producto_nombre: 'Silla', proceso: entrega }])

      resultado = described_class.new(account: account, filtros: {}).casos(pagina: 1)

      expect(resultado[:total]).to eq(2)
      expect(resultado[:pagina]).to eq(1)
      expect(resultado[:paginas]).to eq(1)
      ids = resultado[:casos].map { |fila| fila[:id] }
      expect(ids).to eq([vencida.id, solucionada.id])
      expect(resultado[:casos].first[:vencimiento][:estado]).to eq('rojo')
      expect(resultado[:casos].second[:vencimiento]).to eq(estado: 'solucionada')
      expect(resultado[:casos].second[:etapa]).to eq('solucionada')
    end

    it 'respeta los mismos filtros que los agregados' do
      crear_garantia(abierta_at: Time.zone.local(2026, 1, 1), ciudad: manizales,
                     productos: [{ producto_nombre: 'Cama', proceso: visita }])
      crear_garantia(abierta_at: Time.zone.local(2026, 1, 1), ciudad: pereira,
                     productos: [{ producto_nombre: 'Silla', proceso: visita }])

      resultado = described_class.new(account: account, filtros: { cobertura_ciudad_id: manizales.id })
                                 .casos(pagina: 1)

      expect(resultado[:total]).to eq(1)
      expect(resultado[:casos].first[:centro_operacion]).to eq('Manizales')
    end

    it 'con una pagina fuera de rango, se acomoda a la ultima pagina disponible' do
      crear_garantia(abierta_at: Time.zone.local(2026, 1, 1),
                     productos: [{ producto_nombre: 'Cama', proceso: visita }])

      resultado = described_class.new(account: account, filtros: {}).casos(pagina: 99)

      expect(resultado[:pagina]).to eq(1)
      expect(resultado[:casos].size).to eq(1)
    end
  end
end
