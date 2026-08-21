# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Catalogo::SeederService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  it 'siembra los catalogos con los valores confirmados' do
    resumen = service.sembrar!

    expect(resumen).to eq(
      categorias: 6, tipos: 5, etapas_pqr: 4, motivos_garantia: 5,
      detalles_tipificados: 31, procesos_garantia: 6, coberturas_ciudad: 10
    )
  end

  it 'se ejecuta dos veces seguidas sin generar duplicados (criterio 5)' do
    primera = service.sembrar!
    segunda = described_class.new(account).sembrar!

    expect(segunda).to eq(primera)
  end

  it 'parametriza la regla de los 30 dias como dato (criterio 7)' do
    service.sembrar!

    reparacion = Helic3::Catalogo::MotivoGarantia.find_by!(account: account, codigo: 'reparacion_primera_entrega')
    calidad = Helic3::Catalogo::MotivoGarantia.find_by!(account: account, codigo: 'calidad_producto_comprado')

    expect(reparacion).to have_attributes(regla: 'dias_desde_entrega_maximo', parametro_dias: 30)
    expect(calidad).to have_attributes(regla: 'dias_desde_entrega_minimo', parametro_dias: 31)
  end

  it 'deja los plazos por proceso como dato, no como constante (criterio 6)' do
    service.sembrar!

    plazos = Helic3::Catalogo::ProcesoGarantia.where(account: account)
                                              .pluck(:codigo, :plazo_dias_habiles).to_h
    expect(plazos).to include('visita_tecnica' => 8, 'recoleccion' => 15, 'cambio_producto' => 20)
  end

  it 'marca tecnico propio solo en las ciudades confirmadas' do
    service.sembrar!

    con_tecnico = Helic3::Catalogo::CoberturaCiudad.where(account: account, tecnico_propio: true).pluck(:nombre)
    expect(con_tecnico).to match_array(%w[Armenia Manizales Pereira Cali])
  end

  it 'cuelga cada detalle de su motivo de garantia' do
    service.sembrar!

    chapilla = Helic3::Catalogo::DetalleTipificado.find_by!(account: account, codigo: 'chapilla_leventada')
    expect(chapilla.motivo_garantia.codigo).to eq('calidad_producto_comprado')
  end
end
