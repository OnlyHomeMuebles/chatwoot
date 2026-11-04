# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::PlantillaCorreo do
  let(:account) { create(:account) }
  let(:proceso) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica', codigo: 'visita_tecnica',
                                              posicion: 1)
  end

  def nueva(disparador: 'proceso_garantia', proceso_garantia: proceso, asunto: 'Asunto', cuerpo: 'Cuerpo')
    described_class.new(account: account, disparador: disparador, proceso_garantia: proceso_garantia,
                        asunto: asunto, cuerpo: cuerpo)
  end

  it 'rechaza un disparador invalido' do
    expect(nueva(disparador: 'otro')).not_to be_valid
  end

  it 'exige asunto y cuerpo' do
    plantilla = nueva(asunto: '', cuerpo: '')
    expect(plantilla).not_to be_valid
    expect(plantilla.errors[:asunto]).to be_present
    expect(plantilla.errors[:cuerpo]).to be_present
  end

  it 'una plantilla de proceso_garantia exige el proceso' do
    plantilla = nueva(proceso_garantia: nil)
    expect(plantilla).not_to be_valid
    expect(plantilla.errors[:proceso_garantia]).to be_present
  end

  it 'una plantilla de cierre_caso no admite proceso' do
    plantilla = nueva(disparador: 'cierre_caso', proceso_garantia: proceso)
    expect(plantilla).not_to be_valid
    expect(plantilla.errors[:proceso_garantia]).to be_present
  end

  it 'una plantilla de cierre_caso sin proceso es valida' do
    expect(nueva(disparador: 'cierre_caso', proceso_garantia: nil)).to be_valid
  end

  it 'rechaza un marcador desconocido, p. ej. un error de tipeo' do
    plantilla = nueva(asunto: 'Hola {{CLIETNE}}')
    expect(plantilla).not_to be_valid
    expect(plantilla.errors[:base].join).to include('CLIETNE')
  end

  it 'acepta los marcadores reales de las plantillas de Karen' do
    plantilla = nueva(asunto: 'Tu PQR #{{RADICADO_PQR}}', cuerpo: 'Hola {{CLIENTE}}, tu PQR avanza.')
    expect(plantilla).to be_valid
  end

  it 'no permite dos plantillas para el mismo proceso en la misma cuenta (indice parcial unico)' do
    nueva.save!
    expect { nueva.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'no permite dos plantillas de cierre_caso en la misma cuenta (indice parcial unico)' do
    nueva(disparador: 'cierre_caso', proceso_garantia: nil).save!
    expect { nueva(disparador: 'cierre_caso', proceso_garantia: nil).save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'scope activas devuelve solo las activas' do
    nueva.save!
    inactiva = nueva(disparador: 'cierre_caso', proceso_garantia: nil)
    inactiva.activo = false
    inactiva.save!

    expect(described_class.activas).to contain_exactly(an_object_having_attributes(disparador: 'proceso_garantia'))
  end
end
