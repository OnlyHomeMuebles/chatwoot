# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Catalogo::SeederService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  it 'siembra los catalogos completos del diseno validado' do
    resumen = service.sembrar!

    expect(resumen).to eq(
      categorias: 6, tipos: 5, etapas_pqr: 4, motivos_pqr: 7, resultados: 7,
      motivos_garantia: 5, detalles_tipificados: 31, procesos_garantia: 7,
      coberturas_ciudad: 10, parametros: 9
    )
  end

  it 'se ejecuta dos veces seguidas sin generar duplicados' do
    primera = service.sembrar!
    segunda = described_class.new(account).sembrar!

    expect(segunda).to eq(primera)
  end

  it 'no pisa las ediciones hechas por consola (criterio 7 de CAT-02)' do
    service.sembrar!
    proceso = Helic3::Catalogo::ProcesoGarantia.find_by!(account: account, codigo: 'reparacion_fabrica')
    proceso.update!(plazo_dias_habiles: 12)

    described_class.new(account).sembrar!

    expect(proceso.reload.plazo_dias_habiles).to eq(12)
  end

  it 'siembra los 7 motivos de PQR con su politica de garantia (frente D)' do
    service.sembrar!

    garantia = Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto')
    despacho = Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'error_despacho_entrega')
    retracto = Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'retracto_compra')

    expect(garantia).to be_abre_garantia_siempre
    expect(despacho).to be_abre_garantia_segun_analisis
    expect(retracto).to be_abre_garantia_nunca
    expect(retracto.plazo_dias_habiles).to eq(5)
    expect(garantia.categoria.codigo).to eq('garantia')
  end

  it 'marca la aprobacion humana en los resultados que la exigen (frente C)' do
    service.sembrar!

    con_aprobacion = Helic3::Catalogo::Resultado.where(account: account, aprobacion_humana: true).pluck(:codigo)
    expect(con_aprobacion).to match_array(%w[no_procede_garantia retracto_aprobado])

    trasladada = Helic3::Catalogo::Resultado.find_by!(account: account, codigo: 'trasladada_otra_area')
    expect(trasladada.cierra_pqr).to be(false)
  end

  it 'deja a Respondida como la unica etapa que detiene el reloj legal' do
    service.sembrar!

    detienen = Helic3::Catalogo::EtapaPqr.where(account: account, detiene_reloj: true).pluck(:codigo)
    expect(detienen).to eq(['respondida'])
  end

  it 'asigna el plazo legal de 15 dias a peticion, queja y reclamo' do
    service.sembrar!

    plazos = Helic3::Catalogo::Tipo.where(account: account).pluck(:codigo, :plazo_dias_habiles).to_h
    expect(plazos).to include('peticion' => 15, 'queja' => 15, 'reclamo' => 15,
                              'sugerencia' => nil, 'felicitacion' => nil)
  end

  it 'parametriza la regla de los 30 dias como dato (criterio 7 de CAT-01)' do
    service.sembrar!

    reparacion = Helic3::Catalogo::MotivoGarantia.find_by!(account: account, codigo: 'reparacion_primera_entrega')
    calidad = Helic3::Catalogo::MotivoGarantia.find_by!(account: account, codigo: 'calidad_producto_comprado')

    expect(reparacion).to have_attributes(regla: 'dias_desde_entrega_maximo', parametro_dias: 30)
    expect(calidad).to have_attributes(regla: 'dias_desde_entrega_minimo', parametro_dias: 31)
  end

  it 'siembra el detalle tipificado como catalogo autonomo, sin motivo (frente A)' do
    service.sembrar!

    chapilla = Helic3::Catalogo::DetalleTipificado.find_by!(account: account, codigo: 'chapilla_leventada')
    expect(chapilla.motivo_garantia).to be_nil
  end

  it 'siembra los 7 estados de producto con los plazos confirmados' do
    service.sembrar!

    plazos = Helic3::Catalogo::ProcesoGarantia.where(account: account)
                                              .pluck(:codigo, :plazo_dias_habiles).to_h
    expect(plazos).to include('visita_tecnica' => 8, 'recoleccion' => 15, 'cambio_producto' => 20,
                              'garantia_negada' => nil, 'reparacion_fabrica' => nil)
  end

  it 'marca como terminales solo los desenlaces finales del producto' do
    service.sembrar!

    terminales = Helic3::Catalogo::ProcesoGarantia.where(account: account, es_terminal: true).pluck(:codigo)
    expect(terminales).to match_array(%w[entrega_producto devolucion_dinero garantia_negada])
  end

  it 'define el origen de la ruta segun la cobertura tecnica de la ciudad' do
    service.sembrar!

    cali = Helic3::Catalogo::CoberturaCiudad.find_by!(account: account, codigo: 'cali')
    bogota = Helic3::Catalogo::CoberturaCiudad.find_by!(account: account, codigo: 'bogota')

    expect(cali).to have_attributes(tecnico_propio: true, origen_ruta: 'visita_tecnica')
    expect(bogota).to have_attributes(tecnico_propio: false, origen_ruta: 'recoleccion')
  end

  it 'siembra los parametros de operacion del addendum (frente B)' do
    service.sembrar!

    total = Helic3::Catalogo::Parametro.find_by!(account: account, clave: 'plazo_total_garantia')
    umbral = Helic3::Catalogo::Parametro.find_by!(account: account, clave: 'umbral_confianza_agente')
    direccion = Helic3::Catalogo::Parametro.find_by!(account: account, clave: 'exigir_direccion_confirmada')

    expect(total.valor_entero).to eq(30)
    expect(total.unidad).to eq('dias_habiles')
    expect(umbral.valor_entero).to eq(85)
    expect(direccion.valor_booleano).to be(true)
  end
end
