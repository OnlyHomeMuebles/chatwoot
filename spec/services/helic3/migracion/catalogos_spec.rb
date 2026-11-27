# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Migracion::Catalogos do
  subject(:catalogos) { described_class.new(account: account) }

  let(:account) { create(:account) }
  let!(:responsable) { create(:user, name: 'Experiencia al cliente', account: account) }

  let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia') }
  let!(:tipo) { Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Garantia', codigo: 'garantia') }
  let!(:etapa) do
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Solucionado', codigo: 'solucionado', detiene_reloj: true)
  end
  let!(:resultado) do
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Procede garantía', codigo: 'procede_garantia',
                                        cierra_pqr: true, abre_garantia: true)
  end
  let!(:motivo_pqr) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto', codigo: 'garantia_producto',
                                        categoria: categoria, abre_garantia: :siempre)
  end
  let!(:p_finalizada) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Garantía Finalizada',
                                              codigo: 'garantia_finalizada', es_terminal: true)
  end
  let!(:p_negada) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Garantía negada',
                                              codigo: 'garantia_negada', es_terminal: true)
  end
  let!(:p_cambio) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Cambio de producto',
                                              codigo: 'cambio_producto', plazo_dias_habiles: 20)
  end
  let!(:m_calidad) do
    Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Calidad - producto comprado',
                                             codigo: 'calidad_producto_comprado')
  end
  let!(:detalle) do
    Helic3::Catalogo::DetalleTipificado.create!(account: account, nombre: 'Producto desajustado',
                                                codigo: 'producto_desajustado', motivo_garantia: m_calidad)
  end
  let!(:cobertura) { Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Bogotá', codigo: 'bogota') }

  def caso(etapa:, proceso:, motivo: 'Calidad - Producto Comprado', detalle: 'Producto desajustado', ciudad: 'Cali')
    { etapa_caso: etapa, proceso: proceso, motivo: motivo, ciudad: ciudad,
      productos: [{ nombre: 'MESA', detalle: detalle }] }
  end

  describe '#proceso_para (Tabla 4)' do
    it 'una garantía cerrada va a Garantía Finalizada, aunque la columna diga otra cosa' do
      expect(catalogos.proceso_para(caso(etapa: 'Solucionado', proceso: 'CAMBIO PRODUCTO'))).to eq(p_finalizada)
    end

    it 'una cerrada con GARANTIA NEGADA va a Garantía negada' do
      expect(catalogos.proceso_para(caso(etapa: 'Solucionado', proceso: 'GARANTIA NEGADA'))).to eq(p_negada)
    end

    it 'una abierta usa el proceso de la columna' do
      expect(catalogos.proceso_para(caso(etapa: 'En gestión', proceso: 'CAMBIO PRODUCTO'))).to eq(p_cambio)
    end
  end

  describe '#motivo_para (Tabla 5)' do
    it 'mapea el nombre del DataGrid al código del catálogo' do
      expect(catalogos.motivo_para(caso(etapa: 'Solucionado', proceso: 'PQR FINALIZADA'))).to eq(m_calidad)
    end
  end

  describe '#detalle_para y #cobertura_para (por nombre)' do
    it 'resuelve el detalle por nombre normalizado' do
      expect(catalogos.detalle_para('Producto desajustado')).to eq(detalle)
    end

    it 'resuelve la cobertura quitando el "D.C." de Bogotá' do
      expect(catalogos.cobertura_para('Bogotá, D.C.')).to eq(cobertura)
    end

    it 'devuelve nil si la ciudad no tiene cobertura (no falla)' do
      expect(catalogos.cobertura_para('Leticia')).to be_nil
    end
  end

  describe '#faltantes (validación pre-vuelo)' do
    it 'está vacía cuando el catálogo tiene todo lo que los casos necesitan' do
      casos = [caso(etapa: 'Solucionado', proceso: 'PQR FINALIZADA'),
               caso(etapa: 'En gestión', proceso: 'CAMBIO PRODUCTO')]
      expect(catalogos.faltantes(casos)).to be_empty
    end

    it 'lista el proceso que falta (p.ej. Derecho de petición aún no creado)' do
      casos = [caso(etapa: 'En gestión', proceso: 'DERECHO DE PETICION')]
      expect(catalogos.faltantes(casos)).to include(a_string_matching(/derecho_peticion/))
    end

    it 'lista un detalle tipificado que no existe en el catálogo' do
      casos = [caso(etapa: 'Solucionado', proceso: 'PQR FINALIZADA', detalle: 'Detalle inexistente')]
      expect(catalogos.faltantes(casos)).to include(a_string_matching(/Detalle inexistente/))
    end

    it 'avisa si falta el usuario Experiencia al cliente' do
      responsable.destroy
      expect(described_class.new(account: account).faltantes([])).to include(a_string_matching(/experiencia al cliente/))
    end
  end
end
